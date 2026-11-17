import Foundation
import FlashDictIntegrationContracts
import FlashDictIntegrationKit

nonisolated protocol FlashDictWindowPresenting: Sendable {
    func prepareContextualLookup(presentationID: UUID, anchor: CGRect?) async throws
    func presentContextualLookup(term: String, context: FlashcardCreationContext?, requestID: UUID, anchor: CGRect?, contextIsFragment: Bool) async throws
    func updateContextualLookup(term: String, context: FlashcardCreationContext, presentationID: UUID, contextIsFragment: Bool) async throws
    func dismissContextualLookup(presentationID: UUID) async throws
}
extension FlashDictBridgeClient: FlashDictWindowPresenting {}

/// Orders control messages so a delayed present cannot overtake its matching dismissal.
@MainActor
final class FlashDictWindowSession {
    private let client: (any FlashDictWindowPresenting)?
    private var revision = UUID()
    private var pendingCount = 0
    var hasActiveWindowOrRequests: Bool { presentationID != nil || pendingCount > 0 }
    func waitForStop() async { await operation?.value }
    private var operation: Task<Void, Never>?
    private(set) var presentationID: UUID?
    private var recognizingID: UUID?
    var onFailure: (String, TextLookupCapture) -> Void = { _, _ in }
    init(client: (any FlashDictWindowPresenting)?) { self.client = client }

    func beginRecognition(id: UUID, anchor: CGRect?) async throws {
        if let current = presentationID, current != id { dismiss() }
        presentationID = id
        recognizingID = id
        revision = UUID()
        let revision = revision, previous = operation
        pendingCount += 1
        let preparation = Task { [weak self, client] in
            await previous?.value
            try Task.checkCancellation()
            guard let self, self.presentationID == id, self.revision == revision else { throw CancellationError() }
            do {
                guard let client else { throw FlashDictIntegrationError.requestFailed(message: String(localized: "FlashDict integration is unavailable in this build.")) }
                try await client.prepareContextualLookup(presentationID: id, anchor: anchor)
                try Task.checkCancellation()
            } catch is CancellationError { throw CancellationError() }
            catch { throw FlashDictIntegrationError.requestFailed(message: Self.message(error)) }
        }
        operation = Task { [weak self] in
            defer { self?.pendingCount -= 1 }
            // The caller handles preparation errors; the queue still waits for completion before dismissing.
            _ = try? await preparation.value
        }
        try await withTaskCancellationHandler(operation: { try await preparation.value }, onCancel: { preparation.cancel() })
    }

    func present(_ capture: TextLookupCapture) {
        let completesRecognition = recognizingID == capture.id
        recognizingID = nil
        if let current = presentationID, current != capture.id { dismiss() }
        presentationID = capture.id
        revision = UUID()
        let revision = revision
        let previous = operation
        pendingCount += 1
        operation = Task { [weak self, client] in
            defer { self?.pendingCount -= 1 }
            await previous?.value
            guard let self, self.presentationID == capture.id, self.revision == revision else { return }
            do {
                guard let client else { throw FlashDictIntegrationError.requestFailed(message: String(localized: "FlashDict integration is unavailable in this build.")) }
                if completesRecognition {
                    try await client.updateContextualLookup(term: capture.term, context: Self.context(capture),
                        presentationID: capture.id, contextIsFragment: capture.isContextFragment)
                } else {
                    try await client.presentContextualLookup(term: capture.term, context: Self.context(capture),
                        requestID: capture.id, anchor: capture.anchorRect, contextIsFragment: capture.isContextFragment)
                }
            } catch {
                guard self.presentationID == capture.id, self.revision == revision else { return }
                self.onFailure(Self.message(error), capture)
            }
        }
    }
    func supplement(_ current: TextLookupCapture, sentence: String?, isFragment: Bool) {
        let id = current.id, term = current.term, revision = revision
        guard presentationID == id, let sentence, !sentence.isEmpty else { return }
        let updated = TextLookupCapture(id: id, term: term, sentence: sentence, sourceURL: current.sourceURL,
            anchorRect: current.anchorRect, isContextFragment: isFragment)
        let previous = operation
        pendingCount += 1
        operation = Task { [weak self, client] in
            defer { self?.pendingCount -= 1 }
            await previous?.value
            guard let self, self.presentationID == id, self.revision == revision, let client else { return }
            do { try await client.updateContextualLookup(term: term, context: Self.context(updated), presentationID: id, contextIsFragment: updated.isContextFragment) }
            catch { if self.presentationID == id, self.revision == revision { self.onFailure(Self.message(error), updated) } }
        }
    }
    func dismiss() {
        guard let id = presentationID else { return }
        presentationID = nil
        recognizingID = nil
        revision = UUID()
        let revision = revision
        let previous = operation
        pendingCount += 1
        operation = Task { [weak self, client] in
            defer { self?.pendingCount -= 1 }
            await previous?.value
            do { try await client?.dismissContextualLookup(presentationID: id) }
            catch {
                // The remote window still owns outside-click/Escape closure; don't reopen a local result.
                if self?.revision == revision { self?.onControlFailure?(Self.message(error)) }
            }
        }
    }
    var onControlFailure: ((String) -> Void)?
    private static func context(_ capture: TextLookupCapture) -> FlashcardCreationContext {
        FlashcardCreationContext(sentence: capture.sentence, sourceURL: capture.sourceURL, userNote: nil)
    }
    static func message(_ error: Error) -> String {
        switch error {
        case FlashDictIntegrationError.flashDictNotRunning: String(localized: "Open the matching Debug or Release build of FlashDict, then retry.")
        case FlashDictIntegrationError.incompatibleProtocol: String(localized: "Update Zento and FlashDict to compatible versions.")
        case FlashDictIntegrationError.requestFailed(let message): message ?? String(localized: "FlashDict could not open the lookup window.")
        default: String(localized: "FlashDict could not complete this request.")
        }
    }
}

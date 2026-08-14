import AppKit
import FlashDictIntegrationContracts
import FlashDictIntegrationKit
import Observation

nonisolated protocol TextLookupFlashDictServicing:
    FlashDictLookupProviding,
    FlashDictResourceProviding,
    FlashDictCardCreating {}

extension FlashDictBridgeClient: TextLookupFlashDictServicing {}

nonisolated enum TextLookupDictionaryFailure: Equatable, Sendable {
    case integrationUnavailable
    case flashDictNotRunning
    case primaryDictionaryUnavailable
    case noResult
    case incompatibleProtocol
    case requestFailed(String?)

    var message: String {
        switch self {
        case .integrationUnavailable:
            "FlashDict integration is unavailable in this build."
        case .flashDictNotRunning:
            "Open FlashDict, then try again."
        case .primaryDictionaryUnavailable:
            "Choose a primary dictionary in FlashDict first."
        case .noResult:
            "The primary dictionary has no result for this term."
        case .incompatibleProtocol:
            "Update zbox and FlashDict to compatible versions."
        case .requestFailed(let message):
            message ?? "FlashDict could not complete the lookup."
        }
    }

    var canRetry: Bool {
        switch self {
        case .flashDictNotRunning, .requestFailed: true
        default: false
        }
    }
}

enum TextLookupDictionaryState {
    case idle
    case loading
    case loaded(LookupDocument)
    case failed(TextLookupDictionaryFailure)
}

@MainActor
@Observable
final class TextLookupSessionModel {
    @ObservationIgnored
    private let flashDict: (any TextLookupFlashDictServicing)?
    @ObservationIgnored
    private var lookupTask: Task<Void, Never>?
    @ObservationIgnored
    private var cardTasks: [String: Task<Void, Never>] = [:]

    private(set) var capture: TextLookupCapture?
    private(set) var captureError: TextCaptureError?
    private(set) var dictionaryState: TextLookupDictionaryState = .idle
    private(set) var selectionStates: [String: SenseSelectionState] = [:]
    private(set) var surfaceMessage: String?

    var activeSessionID: UUID? { capture?.id }
    var resourceProvider: (any FlashDictResourceProviding)? { flashDict }

    init(flashDict: (any TextLookupFlashDictServicing)? = nil) {
        self.flashDict = flashDict
    }

    func beginLookup(with capture: TextLookupCapture) {
        cancelWork()
        self.capture = capture
        captureError = nil
        selectionStates = [:]
        surfaceMessage = nil
        startDictionaryLookup(term: capture.term, sessionID: capture.id)
    }

    func present(_ error: TextCaptureError) {
        cancelWork()
        capture = nil
        captureError = error
        dictionaryState = .idle
    }

    func accepts(_ sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }

    func handle(_ event: LookupSurfaceEvent) {
        guard let capture else { return }
        switch event {
        case .senseSelected(let selection):
            createFlashcard(from: selection, capture: capture)
        case .entryRequested(let term, _):
            startDictionaryLookup(term: term, sessionID: capture.id)
        case .flashDictNotRunning:
            dictionaryState = .failed(.flashDictNotRunning)
        case .resourceUnavailable:
            surfaceMessage = "A dictionary resource is unavailable."
        }
    }

    func openFlashDict() {
        let workspace = NSWorkspace.shared
        let url = workspace.urlForApplication(withBundleIdentifier: "tech.hyperseek.flashdict")
            ?? workspace.urlForApplication(withBundleIdentifier: "tech.hyperseek.flashdict.dev")
        guard let url else { return }
        workspace.openApplication(at: url, configuration: .init())
    }

    func retryDictionaryLookup() {
        guard let capture else { return }
        startDictionaryLookup(term: capture.term, sessionID: capture.id)
    }

    func clear() {
        cancelWork()
        capture = nil
        captureError = nil
        dictionaryState = .idle
        selectionStates = [:]
        surfaceMessage = nil
    }

    private func startDictionaryLookup(term: String, sessionID: UUID) {
        lookupTask?.cancel()
        guard let flashDict else {
            dictionaryState = .failed(.integrationUnavailable)
            return
        }

        dictionaryState = .loading
        surfaceMessage = nil
        let requestID = UUID()
        lookupTask = Task { [weak self, flashDict] in
            do {
                let document = try await flashDict.lookup(term: term, requestID: requestID)
                try Task.checkCancellation()
                guard let self, self.accepts(sessionID) else { return }
                dictionaryState = .loaded(document)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.accepts(sessionID) else { return }
                dictionaryState = .failed(Self.map(error))
            }
        }
    }

    private func createFlashcard(
        from selection: SenseSelection,
        capture: TextLookupCapture
    ) {
        guard let flashDict else {
            selectionStates[selection.selectionID] = .failed(
                message: TextLookupDictionaryFailure.integrationUnavailable.message
            )
            return
        }

        let selectionID = selection.selectionID
        let sessionID = capture.id
        cardTasks[selectionID]?.cancel()
        selectionStates[selectionID] = .adding
        let context = FlashcardCreationContext(
            sentence: capture.sentence,
            sourceURL: capture.sourceURL,
            userNote: nil
        )

        cardTasks[selectionID] = Task { [weak self, flashDict] in
            do {
                let result = try await flashDict.createFlashcard(
                    deliveryID: UUID(),
                    seed: selection.cardSeed,
                    context: context
                )
                try Task.checkCancellation()
                guard let self, self.accepts(sessionID) else { return }
                selectionStates[selectionID] = switch result {
                case .added: .added
                case .rejectedQuota: .rejectedQuota
                case .failed(let message): .failed(message: message)
                }
                cardTasks[selectionID] = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.accepts(sessionID) else { return }
                selectionStates[selectionID] = .failed(message: Self.map(error).message)
                cardTasks[selectionID] = nil
            }
        }
    }

    private func cancelWork() {
        lookupTask?.cancel()
        lookupTask = nil
        for task in cardTasks.values { task.cancel() }
        cardTasks = [:]
    }

    private static func map(_ error: Error) -> TextLookupDictionaryFailure {
        guard let error = error as? FlashDictIntegrationError else {
            return .requestFailed(nil)
        }
        return switch error {
        case .flashDictNotRunning: .flashDictNotRunning
        case .primaryDictionaryUnavailable: .primaryDictionaryUnavailable
        case .noResult: .noResult
        case .incompatibleProtocol: .incompatibleProtocol
        case .requestFailed(let message): .requestFailed(message)
        case .resourceUnavailable, .invalidRequest: .requestFailed(nil)
        }
    }
}

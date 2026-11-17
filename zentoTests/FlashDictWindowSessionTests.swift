import Foundation
import CoreGraphics
import Testing
import FlashDictIntegrationContracts
@testable import zento

@MainActor struct FlashDictWindowSessionTests {
    @Test func recognitionResultUpdatesThePreparedWindowInsteadOfPresentingAnother() async throws {
        let (_, continuation) = AsyncStream<Void>.makeStream()
        let client = WindowClient(started: continuation)
        let session = FlashDictWindowSession(client: client)
        let id = UUID()
        try await session.beginRecognition(id: id, anchor: .zero)
        let capture = TextLookupCapture(id: id, term: "word", sentence: "A word in context.", sourceURL: nil, anchorRect: .zero)
        session.present(capture)
        await session.waitForStop()
        #expect(await client.events == ["prepare:\(id)", "update:word"])
        #expect(session.presentationID == id)
        session.dismiss()
        await session.waitForStop()
        session.supplement(capture, sentence: "Late context.", isFragment: false)
        #expect(await client.events == ["prepare:\(id)", "update:word", "dismiss:\(id)"])
    }

    @Test(.timeLimit(.minutes(1))) func delayedPresentIsDismissedBeforeTheNextWindowOpens() async throws {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let client = WindowClient(started: continuation)
        let session = FlashDictWindowSession(client: client)
        let first = TextLookupCapture(id: UUID(), term: "first", sentence: "First context.", sourceURL: nil, anchorRect: nil)
        let second = TextLookupCapture(id: UUID(), term: "second", sentence: "Second context.", sourceURL: nil, anchorRect: nil)
        session.present(first)
        for await _ in started { break }
        session.dismiss()
        session.present(second)
        // An old OCR completion after dismissal/new query must not update either result.
        session.supplement(first, sentence: "Late context.", isFragment: false)
        await client.release()
        let deadline = ContinuousClock.now + .seconds(2)
        while await client.events.count < 3, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let events = await client.events
        #expect(events == ["present:first", "dismiss:\(first.id)", "present:second"])
        #expect(session.presentationID == second.id)
        #expect(await client.sentSentences == ["First context.", "Second context."])
        session.dismiss()
        await session.waitForStop()
        #expect(!session.hasActiveWindowOrRequests)
    }

    private actor WindowClient: FlashDictWindowPresenting {
        func prepareContextualLookup(presentationID: UUID, anchor: CGRect?) async throws { events.append("prepare:\(presentationID)") }
        let started: AsyncStream<Void>.Continuation
        var events: [String] = []
        var sentSentences: [String] = []
        private var waiting: CheckedContinuation<Void, Never>?
        init(started: AsyncStream<Void>.Continuation) { self.started = started }
        func presentContextualLookup(term: String, context: FlashcardCreationContext?, requestID: UUID, anchor: CGRect?, contextIsFragment: Bool) async throws {
            events.append("present:\(term)"); sentSentences.append(context?.sentence ?? "")
            if term == "first" {
                await withCheckedContinuation { waiting = $0; started.yield(()) }
            }
        }
        func release() { waiting?.resume(); waiting = nil }
        func updateContextualLookup(term: String, context: FlashcardCreationContext, presentationID: UUID, contextIsFragment: Bool) async throws { events.append("update:\(term)") }
        func dismissContextualLookup(presentationID: UUID) async throws { events.append("dismiss:\(presentationID)") }
    }
}

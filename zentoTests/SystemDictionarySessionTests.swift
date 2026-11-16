import Foundation
import Testing
import SystemDictionary
@testable import zento

@MainActor struct SystemDictionarySessionTests {
    @Test(.timeLimit(.minutes(1))) func staleSystemLookupFailureCannotReplaceTheNewWord() async throws {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let dictionary = DelayedDictionary(started: continuation)
        let model = TextLookupSessionModel(dictionary: dictionary)
        model.beginLookup(with: TextLookupCapture(id: UUID(), term: "first", sentence: "Original context.", sourceURL: nil, anchorRect: nil), targetLanguageIdentifier: "zh-Hans")
        for await _ in started { break }
        model.selectWord("second")
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if case .loaded = model.dictionaryState { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await dictionary.release()
        for _ in 0..<5 { await Task.yield() }
        #expect(model.activeDictionaryTerm == "second")
        #expect(model.capture?.sentence == "Original context.")
        guard case .loaded = model.dictionaryState else { Issue.record("Old dictionary failure replaced the new result"); return }
        model.clear()
        #expect(model.capture == nil)
    }
    private actor DelayedDictionary: SystemDictionaryReading {
        let started: AsyncStream<Void>.Continuation
        var waiting: CheckedContinuation<Void, Never>?
        init(started: AsyncStream<Void>.Continuation) { self.started = started }
        func lookup(_ term: String) async throws -> [SystemDictionaryEntry] {
            if term == "first" {
                await withCheckedContinuation { waiting = $0; started.yield(()) }
                throw SystemDictionaryError.noResult
            }
            return [SystemDictionaryEntry(id: "fixture", dictionaryName: "Fixture", headword: term,
                html: "<p>Definition</p>", contentsURL: URL(fileURLWithPath: "/tmp/fixture.dictionary/Contents"))]
        }
        func release() { waiting?.resume(); waiting = nil }
    }
}

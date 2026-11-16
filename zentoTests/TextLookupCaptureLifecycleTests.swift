import Foundation
import CoreGraphics
import Testing
@testable import zento

@MainActor
struct TextLookupCaptureLifecycleTests {
    @Test(arguments: [false, true])
    func captureEntryInvalidatesPreviousTranslationBeforeCaptureCompletes(pinned: Bool) throws {
        let suite = "TextLookupCaptureLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = TextLookupSessionModel()
        session.beginLookup(with: TextLookupCapture(id: UUID(), term: "old", sentence: "Old sentence",
            sourceURL: nil, anchorRect: nil), targetLanguageIdentifier: "zh-Hans")
        let previous = try #require(session.translationRequest)
        session.isPinned = pinned
        let plugin = TextLookupPlugin(settings: TextLookupSettingsStore(defaults: defaults),
            clipboardCoordinator: ClipboardAccessCoordinator(),
            capturer: Capturer(), session: session, isAccessibilityTrusted: { true })
        let request = TextCaptureRequest(id: UUID(), intent: .pointerLocation(.zero),
            targetApplicationPID: 0, excludedApplicationPIDs: [], primaryScreenMaxY: 1000,
            triggerAnchorPoint: .zero)
        plugin.beginCapture(request, reportFailure: true) { _ in Issue.record("Cancelled capture completed") }
        #expect(session.capture == nil)
        #expect(session.isPinned == pinned)
        #expect(session.translationRequest == nil)
        session.completeTranslation(TranslationResult(requestID: previous.id, translatedText: "stale"))
        if case .sentenceUnavailable = session.translationState {} else {
            Issue.record("The previous translation was accepted")
        }
        plugin.setShortcutRecordingActive(true)
    }

    @Test func completedRecognitionClearsWhenSourceIsNoLongerForeground() async throws {
        let suite = "TextLookupCaptureLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = TextLookupSessionModel()
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let capturer = RecognizedCapture(session: session, started: continuation)
        let plugin = TextLookupPlugin(settings: TextLookupSettingsStore(defaults: defaults),
            clipboardCoordinator: ClipboardAccessCoordinator(),
            capturer: capturer, session: session, isAccessibilityTrusted: { true })
        let request = TextCaptureRequest(id: UUID(), intent: .pointerLocation(.zero),
            targetApplicationPID: 0, excludedApplicationPIDs: [], primaryScreenMaxY: 1000, triggerAnchorPoint: .zero)
        plugin.beginCapture(request, reportFailure: true) { _ in Issue.record("Published after leaving source app") }
        for await _ in started { break }
        let deadline = ContinuousClock.now + .seconds(1)
        while session.isRecognizingWord && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!session.isRecognizingWord)
        #expect(session.capture == nil)
        plugin.setShortcutRecordingActive(true)
    }

    private struct RecognizedCapture: TextCapturing {
        let session: TextLookupSessionModel
        let started: AsyncStream<Void>.Continuation
        func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture {
            await session.beginOCR()
            started.yield(())
            return TextLookupCapture(id: request.id, term: "word", sentence: "The word has been recognized.",
                                     sourceURL: nil, anchorRect: nil)
        }
    }

    private actor Capturer: TextCapturing {
        func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture {
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
    }
}

import Foundation
import CoreGraphics
import Testing
@testable import zento

@MainActor
struct TextLookupCaptureLifecycleTests {
    @Test func captureEntryInvalidatesPreviousTranslationBeforeCaptureCompletes() throws {
        let suite = "TextLookupCaptureLifecycleTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = TextLookupSessionModel()
        session.beginLookup(with: TextLookupCapture(id: UUID(), term: "old", sentence: "Old sentence",
            sourceURL: nil, anchorRect: nil), targetLanguageIdentifier: "zh-Hans")
        let previous = try #require(session.translationRequest)
        let plugin = TextLookupPlugin(settings: TextLookupSettingsStore(defaults: defaults),
            clipboardCoordinator: ClipboardAccessCoordinator(), hotkeyRegistrar: Registrar(),
            capturer: Capturer(), session: session, isAccessibilityTrusted: { true })
        let request = TextCaptureRequest(id: UUID(), intent: .pointerLocation(.zero),
            targetApplicationPID: 0, excludedApplicationPIDs: [], primaryScreenMaxY: 1000,
            triggerAnchorPoint: .zero)
        plugin.beginCapture(request, reportFailure: true) { _ in Issue.record("Cancelled capture completed") }
        #expect(session.capture == nil)
        #expect(session.translationRequest == nil)
        session.completeTranslation(TranslationResult(requestID: previous.id, translatedText: "stale"))
        if case .sentenceUnavailable = session.translationState {} else {
            Issue.record("The previous translation was accepted")
        }
        plugin.setShortcutRecordingActive(true)
    }

    private actor Capturer: TextCapturing {
        func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture {
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
    }
    private final class Registrar: HotkeyRegistering {
        func replace(ids: Set<String>, with requests: [HotkeyRegistrationRequest]) throws {}
        func setSuspended(_ suspended: Bool) throws {}
        func unregister(id: String) {}
        func unregisterAll() {}
    }
}

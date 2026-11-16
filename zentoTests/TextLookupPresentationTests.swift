import AppKit
import CoreGraphics
import LookupPresentation
import Foundation
import Testing
@testable import zento

struct TextLookupPresentationTests {
    @Test
    func placesPanelBelowThenFallsBackAboveAndClampsHorizontally() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let size = CGSize(width: 520, height: 260)

        let below = LookupPanelPlacement.origin(
            anchor: CGRect(x: 20, y: 600, width: 40, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        #expect(below == CGPoint(x: 12, y: 332))

        let above = LookupPanelPlacement.origin(
            anchor: CGRect(x: 900, y: 30, width: 20, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        #expect(above == CGPoint(x: 468, y: 58))
    }

    @Test @MainActor
    func pinnedPanelKeepsPositionAndSessionUntilExplicitlyClosed() throws {
        let suite = "TextLookupPresentationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TextLookupSessionModel()
        let controller = TextLookupPanelController(model: model, settings: TextLookupSettingsStore(defaults: defaults),
                                                   onDismiss: { model.clear() })
        defer { controller.hide() }
        model.beginLookup(with: capture(id: UUID(), term: "first"), targetLanguageIdentifier: "zh-Hans")
        try controller.show(anchor: CGRect(x: 100, y: 100, width: 10, height: 10))
        let window = try #require(NSApp.windows.first(where: controller.contains))
        #expect(window.isMovableByWindowBackground)
        window.setFrameOrigin(CGPoint(x: window.frame.minX + 30, y: window.frame.minY + 20))
        let originalFrame = window.frame
        model.isPinned = true
        controller.dismissForOutsideClick()
        #expect(window.isVisible)
        #expect(model.capture?.term == "first")

        model.beginLookup(with: capture(id: UUID(), term: "second"), targetLanguageIdentifier: "zh-Hans")
        try controller.show(anchor: CGRect(x: 700, y: 700, width: 10, height: 10))
        #expect(window.frame == originalFrame)
        #expect(model.isPinned)
        window.cancelOperation(nil)
        #expect(!window.isVisible)
        #expect(!model.isPinned)
        #expect(model.capture == nil)

        model.beginLookup(with: capture(id: UUID(), term: "third"), targetLanguageIdentifier: "zh-Hans")
        try controller.show(anchor: nil)
        controller.dismissForOutsideClick()
        #expect(!window.isVisible)
        #expect(model.capture == nil)
    }

    @Test @MainActor
    func clearingInvalidatesThePreviousSession() {
        let model = TextLookupSessionModel()
        model.beginLookup(
            with: capture(id: UUID(), term: "previous"),
            targetLanguageIdentifier: "zh-Hans"
        )

        model.clear()

        #expect(model.capture?.id == nil)
        #expect(model.captureError == nil)
        if case .idle = model.dictionaryState {
            // Clearing releases the previous lookup state.
        } else {
            Issue.record("Expected dictionary state to reset after clearing")
        }
    }

    @Test @MainActor
    func targetLanguageChangeReplacesOnlyTranslationRequest() throws {
        let model = TextLookupSessionModel()
        let capture = TextLookupCapture(
            id: UUID(),
            term: "swift",
            sentence: "Swift is concise.",
            sourceURL: nil,
            anchorRect: nil
        )
        model.beginLookup(with: capture, targetLanguageIdentifier: "zh-Hans")
        let firstRequest = try #require(model.translationRequest)

        model.requestTranslation(targetLanguageIdentifier: "ja")
        let secondRequest = try #require(model.translationRequest)
        model.completeTranslation(
            TranslationResult(
                requestID: firstRequest.id,
                translatedText: "stale"
            )
        )

        #expect(secondRequest.id != firstRequest.id)
        if case .loading = model.translationState {
            // Expected: the stale completion was ignored.
        } else {
            Issue.record("Expected translation to remain loading for the new request")
        }
    }

    @Test @MainActor
    func translationLanguagesAndDownloadConsentBelongToCurrentRequest() throws {
        let model = TextLookupSessionModel()
        let capture = TextLookupCapture(id: UUID(), term: "desktop",
            sentence: "[example/project] GPUI desktop workflow run", sourceURL: nil, anchorRect: nil)
        model.beginLookup(with: capture, targetLanguageIdentifier: "zh-Hans", sourceLanguageIdentifier: "en")
        let first = try #require(model.translationRequest)
        #expect(first.sourceLanguage?.languageCode?.identifier == "en")
        #expect(!first.allowsLanguageDownload)
        model.requireLanguageDownload(requestID: first.id)
        guard case .languageDownloadRequired = model.translationState else {
            Issue.record("Missing languages should require explicit download consent"); return
        }
        model.retryTranslation(allowLanguageDownload: true)
        let consented = try #require(model.translationRequest)
        #expect(consented.id != first.id)
        #expect(consented.sourceLanguage == first.sourceLanguage)
        #expect(consented.targetLanguage == first.targetLanguage)
        #expect(consented.allowsLanguageDownload)
        model.requestTranslation(targetLanguageIdentifier: "ja", sourceLanguageIdentifier: "en")
        let changed = try #require(model.translationRequest)
        #expect(changed.targetLanguage.languageCode?.identifier == "ja")
        #expect(!changed.allowsLanguageDownload)
        model.requireLanguageDownload(requestID: consented.id)
        model.completeTranslation(TranslationResult(requestID: consented.id, translatedText: "stale"))
        guard case .loading = model.translationState else {
            Issue.record("Old requests must not replace the newly selected languages"); return
        }
    }

    @MainActor private func capture(id: UUID, term: String) -> TextLookupCapture {
        TextLookupCapture(id: id, term: term, sentence: nil, sourceURL: nil, anchorRect: nil)
    }
}

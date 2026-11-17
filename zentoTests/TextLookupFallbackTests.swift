import AppKit
import CoreGraphics
import Foundation
import FlashDictIntegrationKit
import Testing
@testable import zento

struct TextLookupFallbackTests {
    @Test func ocrJoinsInlineTextFragmentsWithoutJoiningAnotherColumn() throws {
        let before = TextLookupOCRLine(text: "The doctor is", bounds: CGRect(x: 100, y: 100, width: 90, height: 18), words: [])
        let word = TextLookupOCRLine(text: "diagnosing", bounds: CGRect(x: 195, y: 100, width: 80, height: 18), words: [
            TextLookupOCRWord(range: NSRange(location: 0, length: 10), bounds: CGRect(x: 195, y: 100, width: 80, height: 18))
        ])
        let after = TextLookupOCRLine(text: "the patient.", bounds: CGRect(x: 280, y: 100, width: 100, height: 18), words: [])
        let sidebar = TextLookupOCRLine(text: "Another conversation", bounds: CGRect(x: 450, y: 100, width: 160, height: 18), words: [])
        let result = try #require(TextLookupOCRText.match(lines: [word, sidebar, after, before],
            anchor: CGRect(x: 230, y: 105, width: 1, height: 1), expectedTerm: "diagnosing"))
        #expect(result.term == "diagnosing")
        #expect(result.context == "The doctor is diagnosing the patient.")
    }

    @Test func aWordWithPunctuationStillNeedsContext() {
        let capture = TextLookupCapture(id: UUID(), term: "diagnosing", sentence: "Diagnosing.", sourceURL: nil, anchorRect: nil)
        #expect(capture.needsContext)
    }

    @Test func simulatedInputNeverContinuesAfterPrivacyOrPermissionErrors() {
        for error in [TextCaptureError.secureText, .excludedApplication, .permissionRequired, .selectionTooLong] {
            #expect(!error.allowsCompatibilityFallback)
        }
        #expect(TextCaptureError.unsupportedElement.allowsCompatibilityFallback)
        #expect(TextCaptureError.clipboardFallbackFailed.allowsCompatibilityFallback)
    }

    @Test func ocrWindowSelectionUsesWindowServerOrderAndCoordinates() {
        let frame = CGRect(x: -1200, y: 100, width: 1000, height: 700)
        let target: [String: Any] = [kCGWindowOwnerPID as String: 42, kCGWindowLayer as String: 0,
            kCGWindowBounds as String: frame.dictionaryRepresentation]
        let covering: [String: Any] = [kCGWindowOwnerPID as String: 99, kCGWindowLayer as String: 0,
            kCGWindowBounds as String: frame.dictionaryRepresentation]
        let point = CGPoint(x: -800, y: 400)
        #expect(TextLookupOCRText.windowBounds(at: point, applicationPID: 42, primaryScreenMaxY: 1000,
            windows: [target]) == CGRect(x: -1200, y: 200, width: 1000, height: 700))
        #expect(TextLookupOCRText.windowBounds(at: point, applicationPID: 42, primaryScreenMaxY: 1000,
            windows: [covering, target]) == nil)
        #expect(TextLookupOCRText.windowBounds(at: .zero, applicationPID: 42, primaryScreenMaxY: 1000,
            windows: [target]) == nil)
    }

    // Both runs temporarily register Escape for their popup in this process.
    @MainActor @Test(.serialized, arguments: [TextCaptureError.noTextAtPointer, .secureText])
    func pointerOCRDoesNotRequireAnAccessibleControl(axError: TextCaptureError) async throws {
        let name = "TextLookupOCRFallback.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = TextLookupSettingsStore(defaults: defaults)
        settings.setDoubleClickFallbackEnabled(false)
        let session = TextLookupSessionModel()
        let snapshot = try sampleSnapshot()
        var capturedScreen = false
        var result: TextLookupCapture?
        let plugin = TextLookupPlugin(settings: settings, clipboardCoordinator: ClipboardAccessCoordinator(),
            capturer: UnreadableText(error: axError), captureScreen: { _, _ in
                capturedScreen = true
                return snapshot
            }, session: session, isAccessibilityTrusted: { true })
        defer { plugin.setShortcutRecordingActive(true) }
        // No AX element exists here. The screenshot boundary supplies a known local image instead.
        let point = CGPoint(x: -1_000_000, y: -1_000_000)
        let pid = try #require(NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let request = TextCaptureRequest(id: UUID(), intent: .pointerLocation(point), targetApplicationPID: pid,
            excludedApplicationPIDs: [], primaryScreenMaxY: 1000, triggerAnchorPoint: point)
        plugin.beginCapture(request, reportFailure: true) { result = $0 }
        let deadline = ContinuousClock.now + .seconds(5)
        while result == nil && session.captureError == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(capturedScreen)
        #expect(session.captureError == nil)
        #expect(result?.term == "word")
        #expect(result?.sentence == "Read this word.")
    }

    private struct UnreadableText: TextCapturing {
        let error: TextCaptureError
        func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture { throw error }
    }

    @Test func doubleClickRejectsOldSelectionsAndSelectionsAwayFromPointer() {
        let range = NSRange(location: 12, length: 4)
        let bounds = CGRect(x: 100, y: 100, width: 40, height: 20)
        #expect(DoubleClickTextCapturer.isFreshSelection(range, previous: NSRange(location: 0, length: 0),
            bounds: bounds, point: CGPoint(x: 110, y: 110)))
        #expect(!DoubleClickTextCapturer.isFreshSelection(range, previous: range,
            bounds: bounds, point: CGPoint(x: 110, y: 110)))
        #expect(!DoubleClickTextCapturer.isFreshSelection(range, previous: nil,
            bounds: bounds, point: CGPoint(x: 40, y: 40)))
        #expect(!DoubleClickTextCapturer.isFreshSelection(range, previous: nil,
            bounds: nil, point: CGPoint(x: 110, y: 110)))
    }

    @Test func ocrCropUsesVisibleWindowWidthAndClampsVerticalBand() {
        let screen = CGRect(x: -1600, y: 0, width: 1600, height: 1000)
        let window = CGRect(x: -1700, y: 100, width: 1400, height: 800)
        #expect(TextLookupOCRText.captureRect(point: CGPoint(x: -800, y: 500), window: window, screen: screen)
            == CGRect(x: -1600, y: 340, width: 1300, height: 320))
        #expect(TextLookupOCRText.captureRect(point: CGPoint(x: -800, y: 850), window: window, screen: screen)
            == CGRect(x: -1600, y: 690, width: 1300, height: 210))
        #expect(TextLookupOCRText.captureRect(point: CGPoint(x: -800, y: 500), window: nil, screen: screen) == nil)
    }

    @Test func ocrKeepsLongWrappedSentenceDespiteInterleavedSidebar() throws {
        let texts = ["Previous sentence.", "This is a long", "sentence that spans", "several lines before", "reaching the target", "word at the end."]
        var lines = texts.enumerated().map { index, text in
            TextLookupOCRLine(text: text, bounds: CGRect(x: 200, y: 250 - index * 30, width: 180, height: 20),
                words: index == 5 ? [TextLookupOCRWord(range: NSRange(location: 0, length: 4),
                    bounds: CGRect(x: 200, y: 100, width: 40, height: 20))] : [])
        }
        lines.append(TextLookupOCRLine(text: "Sidebar item", bounds: CGRect(x: 0, y: 205, width: 120, height: 20), words: []))
        let anchor = CGRect(x: 210, y: 110, width: 1, height: 1)
        let match = try #require(TextLookupOCRText.match(lines: lines, anchor: anchor, expectedTerm: nil))
        #expect(match.context == "This is a long sentence that spans several lines before reaching the target word at the end.")
        #expect(!match.isFragment)
        let clipped = try #require(TextLookupOCRText.match(lines: lines, anchor: anchor, expectedTerm: nil,
            cropBounds: CGRect(x: 200, y: 0, width: 600, height: 320)))
        #expect(clipped.isFragment)
    }

    @Test func ocrCoordinatesUseScreenPointsIncludingNegativeDisplayOrigins() {
        let crop = CGRect(x: -900, y: 300, width: 720, height: 240)
        let bounds = TextLookupOCRText.screenRect(CGRect(x: 0.25, y: 0.5, width: 0.1, height: 0.1), crop: crop)
        #expect(bounds == CGRect(x: -720, y: 420, width: 72, height: 24))
    }

    @Test func ocrRequiresSpatialAndTextAgreementAndMarksClippedSentences() throws {
        let line = TextLookupOCRLine(text: "A readable word", bounds: CGRect(x: 0, y: 50, width: 160, height: 20), words: [
            TextLookupOCRWord(range: NSRange(location: 2, length: 8), bounds: CGRect(x: 20, y: 50, width: 80, height: 20)),
        ])
        let anchor = CGRect(x: 50, y: 55, width: 1, height: 1)
        let match = try #require(TextLookupOCRText.match(lines: [line], anchor: anchor, expectedTerm: "Readable"))
        #expect(match.term == "Readable")
        #expect(match.isFragment)
        #expect(match.context == "A readable word")
        #expect(TextLookupOCRText.match(lines: [line], anchor: anchor, expectedTerm: "different") == nil)
        #expect(TextLookupOCRText.match(lines: [line], anchor: CGRect(x: 200, y: 55, width: 1, height: 1), expectedTerm: nil) == nil)
    }

    @Test func ocrJoinsAdjacentLinesButNotOtherColumns() throws {
        let previous = TextLookupOCRLine(text: "Previous sentence.", bounds: CGRect(x: 0, y: 80, width: 160, height: 20), words: [])
        let current = TextLookupOCRLine(text: "Read this word.", bounds: CGRect(x: 0, y: 50, width: 160, height: 20), words: [
            TextLookupOCRWord(range: NSRange(location: 10, length: 4), bounds: CGRect(x: 100, y: 50, width: 40, height: 20)),
        ])
        let anchor = CGRect(x: 110, y: 55, width: 1, height: 1)
        let result = try #require(TextLookupOCRText.match(lines: [previous, current], anchor: anchor, expectedTerm: nil))
        #expect(result.context == "Read this word.")
        #expect(!result.isFragment)
        let otherColumn = TextLookupOCRLine(text: "Unrelated content.", bounds: CGRect(x: 300, y: 80, width: 160, height: 20), words: [])
        let isolated = try #require(TextLookupOCRText.match(lines: [otherColumn, current], anchor: anchor, expectedTerm: nil))
        #expect(isolated.context == "Read this word.")
        #expect(isolated.isFragment)
    }

    @MainActor @Test func visionReadsWordFromLocalImageAtScreenCoordinate() async throws {
        let snapshot = try sampleSnapshot()
        let recognizer = TextLookupOCR()
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await recognizer.recognize(snapshot)
        let secondStart = clock.now
        let repeated = try await recognizer.recognize(snapshot, expectedTerm: "word")
        print("Synthetic local OCR durations: first=\(start.duration(to: secondStart)), repeat=\(secondStart.duration(to: clock.now))")
        #expect(repeated.term == "word")
        #expect(result.term == "word")
        #expect(result.context == "Read this word.")
        #expect(result.isFragment)
    }

    @MainActor private func sampleSnapshot() throws -> TextLookupOCRSnapshot {
        let context = try #require(CGContext(data: nil, width: 600, height: 160, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 160))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black]
        ("Read this word." as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let prefixWidth = ("Read this " as NSString).size(withAttributes: attributes).width
        let image = try #require(context.makeImage())
        return TextLookupOCRSnapshot(image: image, bounds: CGRect(x: -600, y: 300, width: 600, height: 160),
            anchor: CGRect(x: -600 + 30 + prefixWidth + 20, y: 360, width: 1, height: 1))
    }

    @MainActor @Test func contextSupplementPreservesTermAndRejectsStaleSession() throws {
        let session = TextLookupSessionModel()
        let first = TextLookupCapture(id: UUID(), term: "first", sentence: nil, sourceURL: nil, anchorRect: nil)
        let second = TextLookupCapture(id: UUID(), term: "second", sentence: nil, sourceURL: nil, anchorRect: nil)
        session.beginLookup(with: first, targetLanguageIdentifier: "zh-Hans")
        session.setContextStatus(id: first.id, loading: true, message: nil)
        session.beginLookup(with: second, targetLanguageIdentifier: "zh-Hans")
        session.supplementContext(id: first.id, term: "first", text: "Old context.", isFragment: false, targetLanguageIdentifier: "zh-Hans")
        #expect(session.capture?.sentence == nil)
        session.supplementContext(id: second.id, term: "second", text: "Second context.", isFragment: true, targetLanguageIdentifier: "zh-Hans")
        #expect(session.capture?.term == "second")
        #expect(session.capture?.isContextFragment == true)
        #expect(session.translationRequest?.text == "Second context.")
        let translation = try #require(session.translationRequest)
        session.clear()
        session.supplementContext(id: second.id, term: "second", text: "Late context.", isFragment: false, targetLanguageIdentifier: "zh-Hans")
        session.completeTranslation(TranslationResult(requestID: translation.id, translatedText: "Late translation"))
        #expect(session.capture == nil)
        #expect(session.translationRequest == nil)
        #expect(!session.isLoadingContext)
        session.beginLookup(with: first, targetLanguageIdentifier: "zh-Hans")
        session.setContextStatus(id: first.id, loading: true, message: nil)
        session.selectWord("linked")
        session.supplementContext(id: first.id, term: "first", text: "Late context.", isFragment: false, targetLanguageIdentifier: "zh-Hans")
        #expect(session.capture?.sentence == nil)
        #expect(!session.isLoadingContext)
    }

    @MainActor @Test func compatibilitySettingsAreIndependentAndPersisted() throws {
        let name = "TextLookupFallbackTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = TextLookupSettingsStore(defaults: defaults)
        #expect(settings.isDoubleClickFallbackEnabled)
        #expect(settings.isLocalOCREnabled)
        #expect(settings.isClipboardFallbackEnabled)
        settings.setDoubleClickFallbackEnabled(false)
        settings.setClipboardFallbackEnabled(false)
        let reloaded = TextLookupSettingsStore(defaults: defaults)
        #expect(!reloaded.isDoubleClickFallbackEnabled)
        #expect(reloaded.isLocalOCREnabled)
        #expect(!reloaded.isClipboardFallbackEnabled)
        reloaded.setLocalOCREnabled(false)
        #expect(!TextLookupSettingsStore(defaults: defaults).isLocalOCREnabled)
    }
}

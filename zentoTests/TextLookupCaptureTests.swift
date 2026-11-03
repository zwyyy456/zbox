import Foundation
import Testing
@testable import zento

struct TextLookupCaptureTests {
    @Test
    func clipboardFallbackRequiresAReadableNonSecureElement() {
        #expect(TextCaptureError.noSelection.allowsClipboardFallback)
        #expect(TextCaptureError.unableToReadText.allowsClipboardFallback)
        #expect(!TextCaptureError.unsupportedElement.allowsClipboardFallback)
        #expect(!TextCaptureError.secureText.allowsClipboardFallback)
        #expect(!TextCaptureError.permissionRequired.allowsClipboardFallback)
    }

    @Test
    func cleansSelectionWithoutChangingInternalPhrase() throws {
        let cleaned = try TextLookupTextProcessor.cleanSelection("  “state-of-the-art design!”  ")

        #expect(cleaned.term == "state-of-the-art design")
        #expect(cleaned.leadingUTF16Length == 3)
        #expect(cleaned.utf16Length == 23)
    }

    @Test
    func rejectsEmptyAndOversizedSelections() {
        do {
            _ = try TextLookupTextProcessor.cleanSelection(" ... ")
            Issue.record("Expected punctuation-only text to be rejected")
        } catch {
            #expect(error as? TextCaptureError == .noSelection)
        }

        do {
            _ = try TextLookupTextProcessor.cleanSelection("one two three four five six seven eight nine")
            Issue.record("Expected a nine-word selection to be rejected")
        } catch {
            #expect(error as? TextCaptureError == .selectionTooLong)
        }

        #expect(throws: Never.self) {
            _ = try TextLookupTextProcessor.cleanSelection(String(repeating: "a", count: 80))
        }
        #expect(throws: TextCaptureError.selectionTooLong) {
            _ = try TextLookupTextProcessor.cleanSelection(String(repeating: "a", count: 81))
        }
    }

    @Test
    func locatesWordAndContainingSentenceUsingUTF16Offsets() throws {
        let text = "😀 First test works. The second test also works."
        let nsText = text as NSString
        let firstTest = nsText.range(of: "test")
        let targetRange = nsText.range(
            of: "test",
            options: [],
            range: NSRange(
                location: NSMaxRange(firstTest),
                length: nsText.length - NSMaxRange(firstTest)
            )
        )
        _ = try #require(targetRange.location != NSNotFound)
        let wordRange = TextLookupTextProcessor.wordRange(
            in: text,
            containingUTF16Offset: targetRange.location
        )

        #expect(wordRange == targetRange)
        #expect(
            TextLookupTextProcessor.sentence(in: text, containingUTF16Range: targetRange)
                == "The second test also works."
        )
    }

}

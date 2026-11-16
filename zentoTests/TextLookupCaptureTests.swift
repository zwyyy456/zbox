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

    @Test
    func sentenceIncludesInlineLinkPrefixAndCompleteQuotedSpeech() throws {
        let prefix = "CISA’s "
        let link = "Mobile Communications Best Practice Guidance"
        let suffix = " bluntly recommended: “Do not use SMS as a second factor for authentication. SMS messages are not encrypted–a threat actor with access to a telecommunication provider’s network who intercepts these messages can read them.”"
        let previous = "In December 2024, Americans were advised against SMS authentication. "
        let paragraph = previous + prefix + link + suffix
        let target = (paragraph as NSString).range(of: "bluntly")
        #expect(TextLookupTextProcessor.sentence(in: paragraph, containingUTF16Range: target) == prefix + link + suffix)
        let insideQuote = (paragraph as NSString).range(of: "messages")
        #expect(TextLookupTextProcessor.sentence(in: paragraph, containingUTF16Range: insideQuote) == prefix + link + suffix)
        let after = paragraph + " A separate sentence follows."
        #expect(TextLookupTextProcessor.sentence(in: after, containingUTF16Range: target) == prefix + link + suffix)
    }

    @Test
    func unmatchedQuoteDoesNotConsumeFollowingSentences() {
        let text = "A target introduces an unfinished “quotation. A separate sentence follows."
        let target = (text as NSString).range(of: "target")
        #expect(TextLookupTextProcessor.sentence(in: text, containingUTF16Range: target)
                == "A target introduces an unfinished “quotation.")
    }

}

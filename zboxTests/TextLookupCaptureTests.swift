import Foundation
import Testing
@testable import zbox

struct TextLookupCaptureTests {
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
    func detectsOnlyCompleteUninterruptedDoubleOptionTap() {
        var detector = ModifierDoubleTapDetector(maximumInterval: 0.35)

        let firstDown = detector.flagsChanged(keyCode: 58, optionIsDown: true, hasOtherModifiers: false, timestamp: 1.0)
        let firstUp = detector.flagsChanged(keyCode: 58, optionIsDown: false, hasOtherModifiers: false, timestamp: 1.05)
        let secondDown = detector.flagsChanged(keyCode: 58, optionIsDown: true, hasOtherModifiers: false, timestamp: 1.2)
        let secondUp = detector.flagsChanged(keyCode: 58, optionIsDown: false, hasOtherModifiers: false, timestamp: 1.25)
        #expect(!firstDown)
        #expect(!firstUp)
        #expect(!secondDown)
        #expect(secondUp)

        let interruptedFirstDown = detector.flagsChanged(keyCode: 58, optionIsDown: true, hasOtherModifiers: false, timestamp: 2.0)
        let interruptedFirstUp = detector.flagsChanged(keyCode: 58, optionIsDown: false, hasOtherModifiers: false, timestamp: 2.05)
        detector.ordinaryKeyPressed()
        let interruptedSecondDown = detector.flagsChanged(keyCode: 58, optionIsDown: true, hasOtherModifiers: false, timestamp: 2.1)
        let interruptedSecondUp = detector.flagsChanged(keyCode: 58, optionIsDown: false, hasOtherModifiers: false, timestamp: 2.15)
        #expect(!interruptedFirstDown)
        #expect(!interruptedFirstUp)
        #expect(!interruptedSecondDown)
        #expect(!interruptedSecondUp)
    }
}

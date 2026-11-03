import Foundation
import NaturalLanguage

nonisolated enum TextLookupTextProcessor {
    struct CleanedSelection: Sendable {
        let term: String
        let leadingUTF16Length: Int
        let utf16Length: Int
    }

    private static let boundaryCharacters = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    static func cleanSelection(_ text: String) throws -> CleanedSelection {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !boundaryCharacters.contains($0) }),
              let last = scalars.lastIndex(where: { !boundaryCharacters.contains($0) }) else {
            throw TextCaptureError.noSelection
        }

        let end = scalars.index(after: last)
        let term = String(scalars[first..<end])
        let leadingLength = String(scalars[..<first]).utf16.count
        let wordCount = tokenRanges(in: term, unit: .word).count
        guard term.count <= 80, wordCount <= 8 else {
            throw TextCaptureError.selectionTooLong
        }
        guard wordCount > 0 else { throw TextCaptureError.noSelection }

        return CleanedSelection(
            term: term,
            leadingUTF16Length: leadingLength,
            utf16Length: term.utf16.count
        )
    }

    static func wordRange(in text: String, containingUTF16Offset offset: Int) -> NSRange? {
        tokenRanges(in: text, unit: .word).first {
            offset >= $0.location && offset < NSMaxRange($0)
        }
    }

    static func sentence(
        in text: String,
        containingUTF16Range targetRange: NSRange
    ) -> String? {
        guard targetRange.location != NSNotFound else { return nil }
        guard let range = tokenRanges(in: text, unit: .sentence).first(where: {
            targetRange.location >= $0.location && NSMaxRange(targetRange) <= NSMaxRange($0)
        }) else { return nil }
        return (text as NSString).substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenRanges(in text: String, unit: NLTokenUnit) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text
        var ranges: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(NSRange(range, in: text))
            return true
        }
        return ranges
    }
}

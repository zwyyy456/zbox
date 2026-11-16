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

    static func wordRanges(in text: String) -> [NSRange] {
        tokenRanges(in: text, unit: .word)
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
        let sentences = tokenRanges(in: text, unit: .sentence)
        guard var range = sentences.first(where: {
            targetRange.location >= $0.location && NSMaxRange(targetRange) <= NSMaxRange($0)
        }) else { return nil }
        // Keep a reporting clause and its quoted speech together, even when the
        // quote itself contains several sentences. Apostrophes are not quotes.
        let quotes = pairedQuoteRanges(in: text)
        var expanded = true
        while expanded {
            expanded = false
            for quote in quotes where NSIntersectionRange(range, quote).length > 0 {
                let union = NSUnionRange(range, quote)
                guard union != range else { continue }
                let first = sentences.first { NSLocationInRange(union.location, $0) } ?? union
                let last = sentences.first { NSLocationInRange(NSMaxRange(union) - 1, $0) } ?? union
                range = NSUnionRange(first, last)
                expanded = true
            }
        }
        return (text as NSString).substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pairedQuoteRanges(in text: String) -> [NSRange] {
        var stack: [(end: UInt16, start: Int)] = []
        var ranges: [NSRange] = []
        let closers: [UInt16: UInt16] = [0x201c: 0x201d, 0x300c: 0x300d, 0x300e: 0x300f]
        for (index, character) in text.utf16.enumerated() {
            if let top = stack.last, character == top.end {
                stack.removeLast()
                ranges.append(NSRange(location: top.start, length: index - top.start + 1))
            } else if let end = closers[character] {
                stack.append((end, index))
            } else if character == 0x22 {
                stack.append((character, index))
            }
        }
        return ranges
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

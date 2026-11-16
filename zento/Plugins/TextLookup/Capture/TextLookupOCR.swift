import AppKit
import ScreenCaptureKit
import Vision

nonisolated struct TextLookupOCRSnapshot: Sendable {
    let image: CGImage
    let bounds: CGRect
    let anchor: CGRect
}

/// Only the local crop is retained, in memory, until recognition completes.
@MainActor
enum TextLookupScreenCapture {
    static func snapshot(_ request: TextCaptureRequest, anchor: CGRect?) async throws -> TextLookupOCRSnapshot {
        let anchor = anchor ?? request.triggerAnchorRect
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        let target = try TextLookupTargetAccess.validate(request, at: point)
        guard CGPreflightScreenCaptureAccess() else { throw TextCaptureError.screenCapturePermissionRequired }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw TextCaptureError.noTextAtPointer
        }
        let screenFrame = screen.frame
        var crop = CGRect(x: point.x - 360, y: point.y - 120, width: 720, height: 240).intersection(screenFrame)
        if let window = target.windowBounds { crop = crop.intersection(window) }
        guard !crop.isNull, crop.width > 1, crop.height > 1 else { throw TextCaptureError.noTextAtPointer }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        _ = try TextLookupTargetAccess.validate(request, at: point)
        guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
            throw TextCaptureError.noTextAtPointer
        }
        let excluded = content.windows.filter {
            $0.owningApplication.map { request.excludedApplicationPIDs.contains($0.processID) } == true
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.sourceRect = CGRect(x: crop.minX - screenFrame.minX, y: screenFrame.maxY - crop.maxY,
                                   width: crop.width, height: crop.height)
        config.width = max(1, Int((crop.width * CGFloat(filter.pointPixelScale)).rounded()))
        config.height = max(1, Int((crop.height * CGFloat(filter.pointPixelScale)).rounded()))
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        _ = try TextLookupTargetAccess.validate(request, at: point)
        return TextLookupOCRSnapshot(image: image, bounds: crop, anchor: anchor)
    }
}

nonisolated struct TextLookupOCRWord: Sendable {
    let range: NSRange
    let bounds: CGRect
}

nonisolated struct TextLookupOCRLine: Sendable {
    let text: String
    let bounds: CGRect
    let words: [TextLookupOCRWord]
}

nonisolated struct TextLookupOCRMatch: Sendable {
    let term: String
    let context: String?
    let isFragment: Bool
    let bounds: CGRect
}

/// Values are in Cocoa screen points, independently of the display's pixel scale.
nonisolated enum TextLookupOCRText {
    static func screenRect(_ normalized: CGRect, crop: CGRect) -> CGRect {
        CGRect(x: crop.minX + normalized.minX * crop.width,
               y: crop.minY + normalized.minY * crop.height,
               width: normalized.width * crop.width, height: normalized.height * crop.height)
    }

    static func match(lines: [TextLookupOCRLine], anchor: CGRect, expectedTerm: String?) -> TextLookupOCRMatch? {
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        let ordered = lines.sorted { $0.bounds.midY > $1.bounds.midY }
        for (index, line) in ordered.enumerated() {
            for word in line.words where word.bounds.contains(point) {
                let text = line.text as NSString
                guard word.range.location >= 0, NSMaxRange(word.range) <= text.length else { continue }
                let term = text.substring(with: word.range)
                if let expectedTerm, term.compare(expectedTerm, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame { continue }
                guard (try? TextLookupTextProcessor.cleanSelection(term)) != nil else { continue }
                // Only adjacent, aligned lines belong to this context. Never join another column.
                var lower = index
                var upper = index
                while lower > 0 && index - lower < 3 && adjacent(ordered[lower - 1], ordered[lower]) { lower -= 1 }
                while upper + 1 < ordered.count && upper - index < 3 && adjacent(ordered[upper], ordered[upper + 1]) { upper += 1 }
                let prefix = ordered[lower..<index].map(\.text).joined(separator: " ")
                let combined = ordered[lower...upper].map(\.text).joined(separator: " ")
                let offset = prefix.utf16.count + (prefix.isEmpty ? 0 : 1) + word.range.location
                let target = NSRange(location: offset, length: word.range.length)
                let sentence = TextLookupTextProcessor.sentence(in: combined, containingUTF16Range: target)
                // The crop may start midway through a sentence. Only an internal sentence with
                // a terminal punctuation mark can be claimed as complete.
                let sentenceRange = sentence.map { (combined as NSString).range(of: $0, options: [],
                    range: NSRange(location: 0, length: combined.utf16.count)) }
                let complete = sentenceRange.map { $0.location > 0 && $0.location != NSNotFound } == true
                    && sentence?.last.map { ".!?。！？".contains($0) } == true
                return TextLookupOCRMatch(term: expectedTerm ?? term, context: sentence,
                                          isFragment: !complete, bounds: word.bounds)
            }
        }
        return nil
    }

    private static func adjacent(_ top: TextLookupOCRLine, _ bottom: TextLookupOCRLine) -> Bool {
        let height = max(top.bounds.height, bottom.bounds.height)
        let gap = top.bounds.minY - bottom.bounds.maxY
        let overlap = min(top.bounds.maxX, bottom.bounds.maxX) - max(top.bounds.minX, bottom.bounds.minX)
        return gap >= -height * 0.3 && gap <= height * 1.5
            && overlap > min(top.bounds.width, bottom.bounds.width) * 0.5
            && abs(top.bounds.minX - bottom.bounds.minX) <= height * 2
    }
}

actor TextLookupOCR {
    func recognize(_ snapshot: TextLookupOCRSnapshot, expectedTerm: String? = nil) async throws -> TextLookupOCRMatch {
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: snapshot.image)
        try Task.checkCancellation()
        let lines = observations.compactMap { observation -> TextLookupOCRLine? in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.4 else { return nil }
            let text = candidate.string
            // For an existing phrase, match the phrase itself rather than replacing it with one token.
            let ranges: [NSRange]
            if let expectedTerm {
                let ns = text as NSString
                var found: [NSRange] = []
                var location = 0
                while location < ns.length {
                    let range = ns.range(of: expectedTerm, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: NSRange(location: location, length: ns.length - location))
                    guard range.location != NSNotFound, range.length > 0 else { break }
                    let tokens = TextLookupTextProcessor.wordRanges(in: text)
                    if tokens.contains(where: { $0.location == range.location }),
                       tokens.contains(where: { NSMaxRange($0) == NSMaxRange(range) }) {
                        found.append(range)
                    }
                    location = NSMaxRange(range)
                }
                ranges = found
            } else { ranges = TextLookupTextProcessor.wordRanges(in: text) }
            let words = ranges.compactMap { range -> TextLookupOCRWord? in
                guard let stringRange = Range(range, in: text),
                      let box = candidate.boundingBox(for: stringRange) else { return nil }
                return TextLookupOCRWord(range: range, bounds: TextLookupOCRText.screenRect(box.boundingBox.cgRect, crop: snapshot.bounds))
            }
            return TextLookupOCRLine(text: text,
                bounds: TextLookupOCRText.screenRect(observation.boundingBox.cgRect, crop: snapshot.bounds), words: words)
        }
        guard let match = TextLookupOCRText.match(lines: lines, anchor: snapshot.anchor, expectedTerm: expectedTerm) else {
            throw TextCaptureError.noTextAtPointer
        }
        return match
    }
}

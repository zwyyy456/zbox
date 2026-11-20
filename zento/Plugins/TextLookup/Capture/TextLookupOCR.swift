import AppKit
import OSLog
import ScreenCaptureKit
import Vision

nonisolated enum TextLookupOCRDiagnostics {
    static let logger = Logger(subsystem: "tech.hyperseek.zento", category: "TextLookupOCR")

    struct Line {
        let bounds: NormalizedRect
        let confidence: Float?
        let accepted: Bool
        let candidateRanges: Int
        let wordBoxes: Int
    }

    static func logNearbyLines(_ lines: [Line], snapshot: TextLookupOCRSnapshot, id: String) {
        let crop = snapshot.bounds
        let point = CGPoint(x: snapshot.anchor.midX - crop.minX, y: snapshot.anchor.midY - crop.minY)
        let imageSize = CGSize(width: snapshot.image.width, height: snapshot.image.height)
        let projected = lines.enumerated().map { index, line in
            (index: index, line: line, bounds: line.bounds.toImageCoordinates(crop.size, origin: .lowerLeft))
        }
        let covering = projected.count { $0.bounds.contains(point) }
        let rowAtAnchor = projected.count { point.y >= $0.bounds.minY && point.y <= $0.bounds.maxY }
        logger.notice("capture=\(id, privacy: .public) stage=miss-lines anchorImageX=\(Double(point.x * imageSize.width / crop.width)) anchorImageYFromTop=\(Double((crop.height - point.y) * imageSize.height / crop.height)) rawLinesCoveringAnchor=\(covering) rawRowsAtAnchorY=\(rowAtAnchor)")
        let nearby = projected.map { item in
            (item: item, delta: offset(from: point, to: item.bounds))
        }.sorted { hypot($0.delta.x, $0.delta.y) < hypot($1.delta.x, $1.delta.y) }
        for (item, delta) in nearby.prefix(6) {
            let line = item.line
            let raw = line.bounds.cgRect
            let image = line.bounds.toImageCoordinates(imageSize, origin: .upperLeft)
            let mapped = TextLookupOCRText.screenRect(raw, crop: crop)
            logger.notice("capture=\(id, privacy: .public) stage=nearby-line index=\(item.index) hasCandidate=\(line.confidence != nil) confidence=\(Double(line.confidence ?? 0)) accepted=\(line.accepted) candidateRanges=\(line.candidateRanges) wordBoxes=\(line.wordBoxes) containsAnchor=\(item.bounds.contains(point)) dx=\(Double(delta.x)) dy=\(Double(delta.y)) rawX=\(Double(raw.minX)) rawY=\(Double(raw.minY)) rawWidth=\(Double(raw.width)) rawHeight=\(Double(raw.height)) imageX=\(Double(image.minX)) imageYFromTop=\(Double(image.minY)) imageWidth=\(Double(image.width)) imageHeight=\(Double(image.height)) projectionDeltaX=\(Double(mapped.minX - crop.minX - item.bounds.minX)) projectionDeltaY=\(Double(mapped.minY - crop.minY - item.bounds.minY))")
        }
    }

    static func offset(from point: CGPoint, to box: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, box.minX), box.maxX) - point.x,
                y: min(max(point.y, box.minY), box.maxY) - point.y)
    }
}

nonisolated struct TextLookupOCRSnapshot: Sendable {
    let image: CGImage
    let bounds: CGRect
    let anchor: CGRect
}

/// Only the local crop is retained, in memory, until recognition completes.
@MainActor
enum TextLookupScreenCapture {
    static func snapshot(_ request: TextCaptureRequest, anchor: CGRect?) async throws -> TextLookupOCRSnapshot {
        let logger = TextLookupOCRDiagnostics.logger
        let id = request.id.uuidString
        logger.notice("capture=\(id, privacy: .public) stage=snapshot-start context=\(anchor != nil)")
        var stage = "source-validation"
        do {
            let result = try await captureSnapshot(request, anchor: anchor, stage: &stage)
            let crop = result.bounds
            logger.notice("capture=\(id, privacy: .public) stage=snapshot-ready cropWidth=\(Double(crop.width)) cropHeight=\(Double(crop.height)) imageWidth=\(result.image.width) imageHeight=\(result.image.height) anchorX=\(Double(result.anchor.midX - crop.minX)) anchorY=\(Double(result.anchor.midY - crop.minY))")
            return result
        } catch {
            logger.notice("capture=\(id, privacy: .public) stage=snapshot-failed step=\(stage, privacy: .public) cancelled=\(error is CancellationError) code=\((error as NSError).code)")
            throw error
        }
    }

    private static func captureSnapshot(_ request: TextCaptureRequest, anchor: CGRect?,
                                        stage: inout String) async throws -> TextLookupOCRSnapshot {
        let anchor = anchor ?? request.triggerAnchorRect
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        try TextLookupTargetAccess.validateSource(request)
        stage = "screen-permission"
        guard CGPreflightScreenCaptureAccess() else { throw TextCaptureError.screenCapturePermissionRequired }
        stage = "anchor-screen"
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw TextCaptureError.noTextAtPointer
        }
        let screenFrame = screen.frame
        stage = "source-window"
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let window = TextLookupOCRText.windowBounds(at: point, applicationPID: request.targetApplicationPID,
            primaryScreenMaxY: request.primaryScreenMaxY, windows: windows)
        guard let crop = TextLookupOCRText.captureRect(point: point, window: window, screen: screenFrame) else {
            throw TextCaptureError.sourceWindowUnavailable
        }
        stage = "shareable-content"
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        stage = "source-revalidation"
        try Task.checkCancellation()
        try TextLookupTargetAccess.validateSource(request)
        stage = "shareable-display"
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
        let source = config.sourceRect
        let quartzDisplay = CGDisplayBounds(number.uint32Value)
        let quartzAnchor = CGPoint(x: point.x - quartzDisplay.minX - source.minX,
                                   y: request.primaryScreenMaxY - point.y - quartzDisplay.minY - source.minY)
        let sourceAnchor = CGPoint(x: point.x - crop.minX, y: crop.maxY - point.y)
        let pointer = NSEvent.mouseLocation
        let logger = TextLookupOCRDiagnostics.logger
        let id = request.id.uuidString
        logger.notice("capture=\(id, privacy: .public) stage=snapshot-geometry sourceX=\(Double(source.minX)) sourceYFromTop=\(Double(source.minY)) sourceWidth=\(Double(source.width)) sourceHeight=\(Double(source.height)) screenWidth=\(Double(screenFrame.width)) screenHeight=\(Double(screenFrame.height)) quartzWidth=\(Double(quartzDisplay.width)) quartzHeight=\(Double(quartzDisplay.height)) pixelScale=\(Double(filter.pointPixelScale)) requestedWidth=\(config.width) requestedHeight=\(config.height)")
        logger.notice("capture=\(id, privacy: .public) stage=snapshot-anchor sourceX=\(Double(sourceAnchor.x)) sourceYFromTop=\(Double(sourceAnchor.y)) quartzX=\(Double(quartzAnchor.x)) quartzYFromTop=\(Double(quartzAnchor.y)) quartzDeltaX=\(Double(quartzAnchor.x - sourceAnchor.x)) quartzDeltaY=\(Double(quartzAnchor.y - sourceAnchor.y)) pointerDriftX=\(Double(pointer.x - request.triggerAnchorPoint.x)) pointerDriftY=\(Double(pointer.y - request.triggerAnchorPoint.y))")
        stage = "screenshot"
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        stage = "source-revalidation"
        try Task.checkCancellation()
        try TextLookupTargetAccess.validateSource(request)
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
    /// Window Server supplies front-to-back order and top-left-origin frames, without AX text access.
    static func windowBounds(at point: CGPoint, applicationPID: pid_t, primaryScreenMaxY: CGFloat,
                             windows: [[String: Any]]) -> CGRect? {
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { continue }
            let cocoaFrame = CGRect(x: frame.minX, y: primaryScreenMaxY - frame.maxY,
                                    width: frame.width, height: frame.height)
            guard cocoaFrame.contains(point) else { continue }
            // Do not choose a covered source window behind a different application's window.
            return (window[kCGWindowOwnerPID as String] as? Int) == Int(applicationPID) ? cocoaFrame : nil
        }
        return nil
    }

    static func captureRect(point: CGPoint, window: CGRect?, screen: CGRect) -> CGRect? {
        guard let window else { return nil }
        let visible = window.intersection(screen)
        guard !visible.isNull, visible.contains(point) else { return nil }
        let crop = CGRect(x: visible.minX, y: point.y - 160, width: visible.width, height: 320)
            .intersection(visible)
        return crop.width > 1 && crop.height > 1 ? crop : nil
    }

    static func screenRect(_ normalized: CGRect, crop: CGRect) -> CGRect {
        CGRect(x: crop.minX + normalized.minX * crop.width,
               y: crop.minY + normalized.minY * crop.height,
               width: normalized.width * crop.width, height: normalized.height * crop.height)
    }

    static func match(lines: [TextLookupOCRLine], anchor: CGRect, expectedTerm: String?, cropBounds: CGRect? = nil) -> TextLookupOCRMatch? {
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        let ordered = joiningInlineFragments(lines).sorted { $0.bounds.midY > $1.bounds.midY }
        for line in ordered {
            for word in line.words where word.bounds.contains(point) {
                let text = line.text as NSString
                guard word.range.location >= 0, NSMaxRange(word.range) <= text.length else { continue }
                let term = text.substring(with: word.range)
                if let expectedTerm, term.compare(expectedTerm, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame { continue }
                guard (try? TextLookupTextProcessor.cleanSelection(term)) != nil else { continue }
                // Filter the target column before walking adjacent rows: interleaved sidebar
                // observations must neither enter the sentence nor interrupt its wrapped lines.
                let column = ordered.filter { sameColumn($0, line) }
                guard let index = column.firstIndex(where: { $0.bounds == line.bounds && $0.text == line.text }) else { continue }
                var lower = index
                var upper = index
                while lower > 0 && adjacent(column[lower - 1], column[lower]) { lower -= 1 }
                while upper + 1 < column.count && adjacent(column[upper], column[upper + 1]) { upper += 1 }
                let prefix = column[lower..<index].map(\.text).joined(separator: " ")
                let combined = column[lower...upper].map(\.text).joined(separator: " ")
                let offset = prefix.utf16.count + (prefix.isEmpty ? 0 : 1) + word.range.location
                let target = NSRange(location: offset, length: word.range.length)
                let sentence = TextLookupTextProcessor.sentence(in: combined, containingUTF16Range: target)
                // The crop may start midway through a sentence. Only an internal sentence with
                // a terminal punctuation mark can be claimed as complete.
                let sentenceRange = sentence.map { (combined as NSString).range(of: $0, options: [],
                    range: NSRange(location: 0, length: combined.utf16.count)) }
                let touchesCropEdge = cropBounds.map { crop in
                    column[lower...upper].contains {
                        $0.bounds.minX <= crop.minX + 2 || $0.bounds.maxX >= crop.maxX - 2
                            || $0.bounds.minY <= crop.minY + 2 || $0.bounds.maxY >= crop.maxY - 2
                    }
                } ?? false
                let complete = !touchesCropEdge && sentenceRange.map { $0.location > 0 && $0.location != NSNotFound } == true
                    && sentence?.last.map { ".!?。！？".contains($0) } == true
                return TextLookupOCRMatch(term: expectedTerm ?? term, context: sentence,
                                          isFragment: !complete, bounds: word.bounds)
            }
        }
        return nil
    }

    /// Vision can split one visual line at a font/style change. Rejoin nearby fragments
    /// before looking for a paragraph, keeping each word's original screen bounds.
    private static func joiningInlineFragments(_ lines: [TextLookupOCRLine]) -> [TextLookupOCRLine] {
        var joined: [TextLookupOCRLine] = []
        for line in lines.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
            guard let index = joined.firstIndex(where: { previous in
                let height = min(previous.bounds.height, line.bounds.height)
                let overlap = min(previous.bounds.maxY, line.bounds.maxY) - max(previous.bounds.minY, line.bounds.minY)
                let gap = line.bounds.minX - previous.bounds.maxX
                return overlap >= height * 0.65 && abs(previous.bounds.minY - line.bounds.minY) <= height * 0.35
                    && gap >= -1 && gap <= height * 0.75
            }) else {
                joined.append(line)
                continue
            }
            let previous = joined[index]
            let offset = previous.text.utf16.count + 1
            joined[index] = TextLookupOCRLine(text: previous.text + " " + line.text,
                bounds: previous.bounds.union(line.bounds), words: previous.words + line.words.map {
                    TextLookupOCRWord(range: NSRange(location: $0.range.location + offset, length: $0.range.length), bounds: $0.bounds)
                })
        }
        return joined
    }

    private static func sameColumn(_ lhs: TextLookupOCRLine, _ rhs: TextLookupOCRLine) -> Bool {
        let height = max(lhs.bounds.height, rhs.bounds.height)
        let overlap = min(lhs.bounds.maxX, rhs.bounds.maxX) - max(lhs.bounds.minX, rhs.bounds.minX)
        return overlap > min(lhs.bounds.width, rhs.bounds.width) * 0.5
            && abs(lhs.bounds.minX - rhs.bounds.minX) <= height * 2
    }

    private static func adjacent(_ top: TextLookupOCRLine, _ bottom: TextLookupOCRLine) -> Bool {
        let height = max(top.bounds.height, bottom.bounds.height)
        let gap = top.bounds.minY - bottom.bounds.maxY
        return gap >= -height * 0.3 && gap <= height * 1.5 && sameColumn(top, bottom)
    }
}

actor TextLookupOCR {
    func recognize(_ snapshot: TextLookupOCRSnapshot, requestID: UUID,
                   expectedTerm: String? = nil) async throws -> TextLookupOCRMatch {
        try Task.checkCancellation()
        let logger = TextLookupOCRDiagnostics.logger
        let id = requestID.uuidString
        logger.notice("capture=\(id, privacy: .public) stage=recognition-start context=\(expectedTerm != nil)")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: snapshot.image)
            try Task.checkCancellation()
        } catch {
            logger.notice("capture=\(id, privacy: .public) stage=recognition-failed cancelled=\(error is CancellationError) code=\((error as NSError).code)")
            throw error
        }
        var candidateRanges = 0
        var rawLines: [TextLookupOCRDiagnostics.Line] = []
        var boxes: [(raw: NormalizedRect, mapped: CGRect)] = []
        let lines = observations.compactMap { observation -> TextLookupOCRLine? in
            let best = observation.topCandidates(1).first
            guard let candidate = best, candidate.confidence >= 0.4 else {
                rawLines.append(.init(bounds: observation.boundingBox, confidence: best?.confidence, accepted: false,
                                      candidateRanges: 0, wordBoxes: 0))
                return nil
            }
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
            candidateRanges += ranges.count
            let words = ranges.compactMap { range -> TextLookupOCRWord? in
                guard let stringRange = Range(range, in: text),
                      let box = candidate.boundingBox(for: stringRange) else { return nil }
                let raw = box.boundingBox
                let mapped = TextLookupOCRText.screenRect(raw.cgRect, crop: snapshot.bounds)
                boxes.append((raw, mapped))
                return TextLookupOCRWord(range: range, bounds: mapped)
            }
            rawLines.append(.init(bounds: observation.boundingBox, confidence: candidate.confidence, accepted: true,
                                  candidateRanges: ranges.count, wordBoxes: words.count))
            return TextLookupOCRLine(text: text,
                bounds: TextLookupOCRText.screenRect(observation.boundingBox.cgRect, crop: snapshot.bounds), words: words)
        }
        let point = CGPoint(x: snapshot.anchor.midX, y: snapshot.anchor.midY)
        let coveringBoxes = boxes.count(where: { $0.mapped.contains(point) })
        logger.notice("capture=\(id, privacy: .public) stage=recognition-ready observations=\(observations.count) acceptedLines=\(lines.count) candidateRanges=\(candidateRanges) wordBoxes=\(boxes.count) coveringBoxes=\(coveringBoxes)")
        guard let match = TextLookupOCRText.match(lines: lines, anchor: snapshot.anchor, expectedTerm: expectedTerm, cropBounds: snapshot.bounds) else {
            TextLookupOCRDiagnostics.logNearbyLines(rawLines, snapshot: snapshot, id: id)
            let nearest = boxes.lazy.map {
                (raw: $0.raw.cgRect, delta: TextLookupOCRDiagnostics.offset(from: point, to: $0.mapped))
            }.min { hypot($0.delta.x, $0.delta.y) < hypot($1.delta.x, $1.delta.y) }
            if let (raw, delta) = nearest {
                logger.notice("capture=\(id, privacy: .public) stage=match-miss nearestDX=\(Double(delta.x)) nearestDY=\(Double(delta.y)) rawWordX=\(Double(raw.minX)) rawWordY=\(Double(raw.minY)) rawWordWidth=\(Double(raw.width)) rawWordHeight=\(Double(raw.height))")
            } else {
                logger.notice("capture=\(id, privacy: .public) stage=match-miss noWordBoxes=true")
            }
            throw TextCaptureError.noTextAtPointer
        }
        logger.notice("capture=\(id, privacy: .public) stage=match-hit")
        return match
    }
}

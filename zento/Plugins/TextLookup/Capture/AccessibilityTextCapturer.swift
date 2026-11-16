import ApplicationServices
import Foundation
import OSLog
import Carbon

actor AccessibilityTextCapturer: TextCapturing {
    private let contextRadius = 1_024
    private let logger = Logger(subsystem: "tech.hyperseek.zento", category: "TextLookupCapture")
    // AX calls below are synchronous and actor-isolated; no capture can interleave this scope.
    private var diagnosticID = ""

    private func trace(_ stage: String) {
        logger.notice("[TextLookupCapture] capture=\(self.diagnosticID, privacy: .public) stage=\(stage, privacy: .public)")
    }

    private func traceAX(_ attribute: String, result: AXError, hasValue: Bool) {
        // Only our constant attribute names and result codes; never log parameters or returned text.
        logger.info("[TextLookupCapture] capture=\(self.diagnosticID, privacy: .public) api=\(attribute, privacy: .public) result=\(result.rawValue) hasValue=\(hasValue)")
    }

    private func traceRole(_ element: AXUIElement, depth: Int) {
        let role = stringAttribute(element, "AXRole")
        let knownRoles = ["AXStaticText", "AXTextField", "AXTextArea", "AXGroup", "AXWebArea",
                          "AXWindow", "AXScrollArea", "AXApplication", "AXButton", "AXUnknown"]
        // A custom role is external input and could contain arbitrary data.
        let safeRole = role.flatMap { knownRoles.contains($0) ? $0 : nil } ?? "other-or-unavailable"
        logger.notice("[TextLookupCapture] capture=\(self.diagnosticID, privacy: .public) depth=\(depth) role=\(safeRole, privacy: .public)")
    }

    func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture {
        diagnosticID = request.id.uuidString
        defer { diagnosticID = "" }
        trace(request.intent.allowsClipboardFallback ? "selection-start" : "pointer-start")
        defer { trace("capture-ended") }
        try Task.checkCancellation()
        guard !IsSecureEventInputEnabled() else { throw TextCaptureError.secureText }
        guard AXIsProcessTrusted() else { throw TextCaptureError.permissionRequired }
        switch request.intent {
        case .currentSelection:
            return try captureSelection(request)
        case .pointerLocation(let point):
            return try capturePointer(point, request: request)
        }
    }

    private func captureSelection(_ request: TextCaptureRequest) throws -> TextLookupCapture {
        if request.excludedApplicationPIDs.contains(request.targetApplicationPID) {
            throw TextCaptureError.excludedApplication
        }
        let application = AXUIElementCreateApplication(request.targetApplicationPID)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let element = elementAttribute(application, "AXFocusedUIElement") else {
            throw TextCaptureError.unsupportedElement
        }
        try rejectSecureText(element)

        let selectedRange = rangeAttribute(element, "AXSelectedTextRange")
        let selectedText = stringAttribute(element, "AXSelectedText")
            ?? selectedRange.flatMap { $0.length > 0 ? stringForRange($0, in: element) : nil }
            ?? rawAttribute(element, "AXSelectedTextMarkerRange").flatMap {
                parameterized(element, "AXStringForTextMarkerRange", $0) as? String
            }
        guard let selectedText, !selectedText.isEmpty else { throw TextCaptureError.noSelection }
        let cleaned = try TextLookupTextProcessor.cleanSelection(selectedText)
        let termRange = selectedRange.map {
            CFRange(location: $0.location + cleaned.leadingUTF16Length, length: cleaned.utf16Length)
        }
        let sentence = termRange.flatMap { range in
            context(around: range, in: element).flatMap {
                TextLookupTextProcessor.sentence(
                    in: $0.text,
                    containingUTF16Range: NSRange(location: range.location - $0.globalLocation, length: range.length)
                )
            }
        }
        return TextLookupCapture(
            id: request.id, term: cleaned.term, sentence: sentence,
            sourceURL: sourceURL(from: element),
            anchorRect: termRange.flatMap {
                cocoaBounds(for: $0, in: element, primaryMaxY: request.primaryScreenMaxY)
            } ?? request.triggerAnchorRect
        )
    }

    private func capturePointer(
        _ cocoaPoint: CGPoint,
        request: TextCaptureRequest
    ) throws -> TextLookupCapture {
        let systemWide = AXUIElementCreateSystemWide()
        let axPoint = CGPoint(x: cocoaPoint.x, y: request.primaryScreenMaxY - cocoaPoint.y)
        var hit: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(axPoint.x),
            Float(axPoint.y),
            &hit
        )
        traceAX("AXElementAtPosition", result: hitResult, hasValue: hit != nil)
        guard hitResult == .success, let element = hit else {
            throw TextCaptureError.noTextAtPointer
        }
        var hitPID: pid_t = 0
        AXUIElementGetPid(element, &hitPID)
        if request.excludedApplicationPIDs.contains(hitPID) {
            throw TextCaptureError.excludedApplication
        }
        try rejectSecureText(element)

        // Hit testing can return a leaf while the text APIs belong to its text container.
        var current: AXUIElement? = element
        var visited: [AXUIElement] = []
        for depth in 0..<8 {
            try Task.checkCancellation()
            guard let candidate = current,
                  !visited.contains(where: { CFEqual($0, candidate) }) else { break }
            visited.append(candidate)
            traceRole(candidate, depth: depth)
            if let capture = captureRange(at: axPoint, in: candidate, request: request)
                ?? captureMarker(at: axPoint, in: candidate, request: request)
                ?? captureStaticText(at: axPoint, in: candidate, request: request) {
                return capture
            }
            current = elementAttribute(candidate, "AXParent")
            if let parent = current, stringAttribute(parent, "AXRole") == "AXApplication" { break }
        }
        trace("pointer-no-matching-text")
        throw TextCaptureError.unsupportedElement
    }

    private func captureRange(
        at point: CGPoint, in element: AXUIElement, request: TextCaptureRequest
    ) -> TextLookupCapture? {
        guard let characterRange = rangeForPosition(point, in: element) else {
            trace("range-position-unavailable")
            return nil
        }
        guard let context = context(around: characterRange, in: element) else {
            trace("range-context-unavailable")
            return nil
        }
        guard let word = TextLookupTextProcessor.wordRange(
                in: context.text, containingUTF16Offset: characterRange.location - context.globalLocation
              ) else {
            trace("range-no-word-at-offset")
            return nil
        }
        let range = CFRange(location: context.globalLocation + word.location, length: word.length)
        // Some controls return the nearest insertion point even outside their text.
        if let bounds = boundsForRange(range, in: element), !bounds.contains(point) {
            trace("range-bounds-miss")
            return nil
        }
        trace("range-success")
        return TextLookupCapture(
            id: request.id, term: (context.text as NSString).substring(with: word),
            sentence: TextLookupTextProcessor.sentence(in: context.text, containingUTF16Range: word),
            sourceURL: sourceURL(from: element),
            anchorRect: cocoaBounds(for: range, in: element, primaryMaxY: request.primaryScreenMaxY)
                ?? request.triggerAnchorRect
        )
    }

    private func captureStaticText(
        at point: CGPoint, in element: AXUIElement, request: TextCaptureRequest
    ) -> TextLookupCapture? {
        guard stringAttribute(element, "AXRole") == "AXStaticText",
              let text = stringAttribute(element, "AXValue"), text.utf16.count <= contextRadius * 2 else { return nil }
        // Only read this leaf's text. Do not fetch AXValue from a whole document/editor.
        trace("static-text-readable")
        let words = TextLookupTextProcessor.wordRanges(in: text)
        for word in words {
            let range = CFRange(location: word.location, length: word.length)
            guard let bounds = boundsForRange(range, in: element), bounds.contains(point) else { continue }
            trace("static-text-success")
            return TextLookupCapture(
                id: request.id, term: (text as NSString).substring(with: word),
                sentence: TextLookupTextProcessor.sentence(in: text, containingUTF16Range: word),
                sourceURL: sourceURL(from: element),
                anchorRect: CGRect(x: bounds.minX, y: request.primaryScreenMaxY - bounds.maxY,
                                   width: bounds.width, height: bounds.height)
            )
        }
        trace("static-text-no-matching-word-bounds")
        return nil
    }

    private func captureMarker(
        at point: CGPoint, in element: AXUIElement, request: TextCaptureRequest
    ) -> TextLookupCapture? {
        var point = point
        guard let position = AXValueCreate(.cgPoint, &point),
              let marker = parameterized(element, "AXTextMarkerForPosition", position) else { return nil }
        // WebKit and Chromium expose opaque text markers rather than integer character ranges.
        for attribute in ["AXLeftWordTextMarkerRangeForTextMarker", "AXRightWordTextMarkerRangeForTextMarker"] {
            guard let range = parameterized(element, attribute, marker) else {
                trace("marker-word-range-unavailable")
                continue
            }
            guard let bounds = rectValue(parameterized(element, "AXBoundsForTextMarkerRange", range)) else {
                trace("marker-word-bounds-unavailable")
                continue
            }
            guard bounds.contains(point) else {
                trace("marker-word-bounds-miss")
                continue
            }
            guard let text = parameterized(element, "AXStringForTextMarkerRange", range) as? String else {
                trace("marker-word-text-unavailable")
                continue
            }
            guard let cleaned = try? TextLookupTextProcessor.cleanSelection(text) else {
                trace("marker-word-text-rejected")
                continue
            }
            trace("marker-success")
            return TextLookupCapture(
                id: request.id, term: cleaned.term, sentence: nil,
                sourceURL: sourceURL(from: element),
                anchorRect: CGRect(x: bounds.minX, y: request.primaryScreenMaxY - bounds.maxY,
                                   width: bounds.width, height: bounds.height)
            )
        }
        trace("marker-no-matching-word")
        return nil
    }

    private func parameterized(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        traceAX(attribute, result: result, hasValue: value != nil)
        guard result == .success else {
            return nil
        }
        return value
    }

    private func rectValue(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var bounds = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &bounds) ? bounds : nil
    }

    private func rejectSecureText(_ element: AXUIElement) throws {
        var current: AXUIElement? = element
        var visited: Set<ObjectIdentifier> = []
        while let candidate = current {
            guard visited.insert(ObjectIdentifier(candidate)).inserted else { break }
            if stringAttribute(candidate, "AXSubrole") == "AXSecureTextField" {
                throw TextCaptureError.secureText
            }
            current = elementAttribute(candidate, "AXParent")
        }
    }

    private func context(
        around range: CFRange,
        in element: AXUIElement
    ) -> (text: String, globalLocation: Int)? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        if let totalLength = integerAttribute(element, "AXNumberOfCharacters"), totalLength > 0 {
            let location = max(0, range.location - contextRadius)
            let end = min(totalLength, range.location + range.length + contextRadius)
            if end > location,
               let text = stringForRange(CFRange(location: location, length: end - location), in: element) {
                return (text, location)
            }
        }
        // Character count and a full sentence are optional. A bounded line is sufficient.
        if let line = parameterized(element, "AXLineForIndex", NSNumber(value: range.location)),
           let value = parameterized(element, "AXRangeForLine", line),
           CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = unsafeDowncast(value, to: AXValue.self)
            var lineRange = CFRange()
            if AXValueGetType(axValue) == .cfRange,
               AXValueGetValue(axValue, .cfRange, &lineRange),
               lineRange.location >= 0, lineRange.length > 0, lineRange.length <= contextRadius * 2,
               let text = stringForRange(lineRange, in: element) {
                return (text, lineRange.location)
            }
        }
        return nil
    }

    private func sourceURL(from element: AXUIElement) -> URL? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { break }
            if let value = rawAttribute(candidate, "AXURL") {
                if let url = value as? URL { return url }
                if let string = value as? String, let url = URL(string: string) { return url }
            }
            current = elementAttribute(candidate, "AXParent")
        }
        return nil
    }

    private func cocoaBounds(
        for range: CFRange,
        in element: AXUIElement,
        primaryMaxY: CGFloat
    ) -> CGRect? {
        guard let axBounds = boundsForRange(range, in: element) else { return nil }
        return CGRect(
            x: axBounds.minX,
            y: primaryMaxY - axBounds.maxY,
            width: axBounds.width,
            height: axBounds.height
        )
    }

    private func rawAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        traceAX(attribute, result: result, hasValue: value != nil)
        guard result == .success else {
            return nil
        }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = rawAttribute(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        rawAttribute(element, attribute) as? String
    }

    private func integerAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        (rawAttribute(element, attribute) as? NSNumber)?.intValue
    }

    private func rangeAttribute(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = rawAttribute(element, attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func stringForRange(_ range: CFRange, in element: AXUIElement) -> String? {
        var mutableRange = range
        guard let parameter = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        return parameterized(element, "AXStringForRange", parameter) as? String
    }

    private func rangeForPosition(_ point: CGPoint, in element: AXUIElement) -> CFRange? {
        var mutablePoint = point
        guard let parameter = AXValueCreate(.cgPoint, &mutablePoint) else { return nil }
        guard let value = parameterized(element, "AXRangeForPosition", parameter),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func boundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = range
        guard let parameter = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        return rectValue(parameterized(element, "AXBoundsForRange", parameter))
    }
}

import ApplicationServices
import Foundation

actor AccessibilityTextCapturer: TextCapturing {
    private let contextRadius = 1_024

    func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw TextCaptureError.permissionRequired }
        switch request.intent {
        case .currentSelection:
            return try captureSelection(request)
        case .pointerLocation(let point):
            return try capturePointer(point, request: request)
        }
    }

    private func captureSelection(_ request: TextCaptureRequest) throws -> TextLookupCapture {
        if let bundleIdentifier = request.targetApplicationBundleIdentifier,
           request.excludedApplicationBundleIdentifiers.contains(bundleIdentifier) {
            throw TextCaptureError.excludedApplication
        }
        let application = AXUIElementCreateApplication(request.targetApplicationPID)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let element = elementAttribute(application, "AXFocusedUIElement") else {
            throw TextCaptureError.unsupportedElement
        }
        try rejectSecureText(element)

        guard let selectedRange = rangeAttribute(element, "AXSelectedTextRange"),
              selectedRange.length > 0 else {
            throw TextCaptureError.noSelection
        }
        guard let selectedText = stringAttribute(element, "AXSelectedText")
            ?? stringForRange(selectedRange, in: element) else {
            throw TextCaptureError.unableToReadText
        }

        let cleaned = try TextLookupTextProcessor.cleanSelection(selectedText)
        let termRange = CFRange(
            location: selectedRange.location + cleaned.leadingUTF16Length,
            length: cleaned.utf16Length
        )
        let context = context(around: termRange, in: element)
        let sentence = context.flatMap {
            TextLookupTextProcessor.sentence(
                in: $0.text,
                containingUTF16Range: NSRange(
                    location: termRange.location - $0.globalLocation,
                    length: termRange.length
                )
            )
        }

        return TextLookupCapture(
            id: request.id,
            term: cleaned.term,
            sentence: sentence,
            sourceURL: sourceURL(from: element),
            anchorRect: cocoaBounds(
                for: termRange,
                in: element,
                primaryMaxY: request.primaryScreenMaxY
            ) ?? request.triggerAnchorRect,
            sourceApplicationBundleIdentifier: request.targetApplicationBundleIdentifier
        )
    }

    private func capturePointer(
        _ cocoaPoint: CGPoint,
        request: TextCaptureRequest
    ) throws -> TextLookupCapture {
        let systemWide = AXUIElementCreateSystemWide()
        let axPoint = CGPoint(x: cocoaPoint.x, y: request.primaryScreenMaxY - cocoaPoint.y)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(axPoint.x),
            Float(axPoint.y),
            &hit
        ) == .success, let element = hit else {
            throw TextCaptureError.noTextAtPointer
        }
        var hitPID: pid_t = 0
        AXUIElementGetPid(element, &hitPID)
        let bundleIdentifier = request.applicationBundleIdentifiersByPID[hitPID]
        if let bundleIdentifier,
           request.excludedApplicationBundleIdentifiers.contains(bundleIdentifier) {
            throw TextCaptureError.excludedApplication
        }
        try rejectSecureText(element)

        guard let characterRange = rangeForPosition(axPoint, in: element) else {
            throw TextCaptureError.unsupportedElement
        }
        guard let context = context(around: characterRange, in: element) else {
            throw TextCaptureError.unableToReadText
        }
        let relativeOffset = characterRange.location - context.globalLocation
        guard let relativeWordRange = TextLookupTextProcessor.wordRange(
            in: context.text,
            containingUTF16Offset: relativeOffset
        ) else {
            throw TextCaptureError.noTextAtPointer
        }

        let term = (context.text as NSString).substring(with: relativeWordRange)
        let wordRange = CFRange(
            location: context.globalLocation + relativeWordRange.location,
            length: relativeWordRange.length
        )
        let sentence = TextLookupTextProcessor.sentence(
            in: context.text,
            containingUTF16Range: relativeWordRange
        )

        return TextLookupCapture(
            id: request.id,
            term: term,
            sentence: sentence,
            sourceURL: sourceURL(from: element),
            anchorRect: cocoaBounds(
                for: wordRange,
                in: element,
                primaryMaxY: request.primaryScreenMaxY
            ) ?? request.triggerAnchorRect,
            sourceApplicationBundleIdentifier: bundleIdentifier
        )
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
        let totalLength = integerAttribute(element, "AXNumberOfCharacters")
        guard let totalLength, totalLength > 0 else { return nil }

        let location = max(0, range.location - contextRadius)
        let end = min(totalLength, NSMaxRange(NSRange(location: range.location, length: range.length)) + contextRadius)
        let contextRange = CFRange(location: location, length: max(0, end - location))
        return stringForRange(contextRange, in: element).map { ($0, location) }
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
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
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
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForRange" as CFString,
            parameter,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private func rangeForPosition(_ point: CGPoint, in element: AXUIElement) -> CFRange? {
        var mutablePoint = point
        guard let parameter = AXValueCreate(.cgPoint, &mutablePoint) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXRangeForPosition" as CFString,
            parameter,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func boundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = range
        guard let parameter = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForRange" as CFString,
            parameter,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var bounds = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &bounds) ? bounds : nil
    }
}

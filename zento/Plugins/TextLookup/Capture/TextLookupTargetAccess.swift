import AppKit
import ApplicationServices
import Carbon

/// Revalidates the source before a compatibility action or a screen read.
@MainActor
enum TextLookupTargetAccess {
    static let syntheticEventTag: Int64 = 0x5A544C4F4F4B

    struct Target {
        let element: AXUIElement
        let canDoubleClick: Bool
        let windowBounds: CGRect?
    }

    static func validate(_ request: TextCaptureRequest, at point: CGPoint? = nil) throws -> Target {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw TextCaptureError.permissionRequired }
        guard !IsSecureEventInputEnabled() else { throw TextCaptureError.secureText }
        guard !request.excludedApplicationPIDs.contains(request.targetApplicationPID) else {
            throw TextCaptureError.excludedApplication
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == request.targetApplicationPID else {
            throw CancellationError()
        }
        let point = point ?? request.triggerAnchorPoint
        let axPoint = CGPoint(x: point.x, y: request.primaryScreenMaxY - point.y)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(axPoint.x), Float(axPoint.y), &hit) == .success,
              let hit else { throw TextCaptureError.noTextAtPointer }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid == request.targetApplicationPID else {
            throw CancellationError()
        }
        var current: AXUIElement? = hit
        var visited: [AXUIElement] = []
        var canDoubleClick = false
        var actionable = false
        var windowBounds: CGRect?
        for depth in 0..<24 {
            guard let node = current else { break }
            guard !visited.contains(where: { CFEqual($0, node) }) else { throw TextCaptureError.secureText }
            visited.append(node)
            if value(node, "AXSubrole") as? String == "AXSecureTextField" { throw TextCaptureError.secureText }
            guard let role = value(node, "AXRole") as? String else { throw TextCaptureError.unsupportedElement }
            if depth == 0 { canDoubleClick = ["AXStaticText", "AXTextField", "AXTextArea"].contains(role) }
            if ["AXLink", "AXButton", "AXMenuItem", "AXPopUpButton", "AXComboBox"].contains(role) { actionable = true }
            var actions: CFArray?
            if AXUIElementCopyActionNames(node, &actions) == .success,
               (actions as? [String])?.contains("AXPress") == true { actionable = true }
            if role == "AXWindow" { windowBounds = frame(node, primaryMaxY: request.primaryScreenMaxY) }
            if role == "AXApplication" {
                return Target(element: hit, canDoubleClick: canDoubleClick && !actionable, windowBounds: windowBounds)
            }
            current = element(value(node, "AXParent"))
        }
        // An incomplete ancestry cannot establish whether the target is protected text.
        throw TextCaptureError.unsupportedElement
    }

    static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let value = value(element, "AXSelectedTextRange"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func bounds(_ range: NSRange, in element: AXUIElement) -> CGRect? {
        var range = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForRange" as CFString, parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        let ax = unsafeDowncast(result, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(ax) == .cgRect, AXValueGetValue(ax, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func frame(_ element: AXUIElement, primaryMaxY: CGFloat) -> CGRect? {
        guard let position = value(element, "AXPosition"), let size = value(element, "AXSize"),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let axPosition = unsafeDowncast(position, to: AXValue.self)
        let axSize = unsafeDowncast(size, to: AXValue.self)
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetType(axPosition) == .cgPoint, AXValueGetType(axSize) == .cgSize,
              AXValueGetValue(axPosition, .cgPoint, &origin), AXValueGetValue(axSize, .cgSize, &extent) else { return nil }
        return CGRect(x: origin.x, y: primaryMaxY - origin.y - extent.height, width: extent.width, height: extent.height)
    }
}

@MainActor
struct DoubleClickTextCapturer {
    func capture(_ request: TextCaptureRequest, capturer: any TextCapturing,
                 clipboard: ClipboardSelectionCapturer, allowClipboard: Bool) async throws -> TextLookupCapture? {
        guard case .pointerLocation(let point) = request.intent else { return nil }
        let target = try TextLookupTargetAccess.validate(request)
        guard target.canDoubleClick else { return nil }
        let originalRange = TextLookupTargetAccess.selectedRange(target.element)
        let axPoint = CGPoint(x: point.x, y: request.primaryScreenMaxY - point.y)
        guard hypot(NSEvent.mouseLocation.x - point.x, NSEvent.mouseLocation.y - point.y) <= 4 else { throw CancellationError() }
        let source = CGEventSource(stateID: .privateState)
        // Set no modifier flags: the lookup shortcut may still be physically held.
        for count in 1...2 {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: axPoint, mouseButton: .left) else {
                    throw TextCaptureError.unableToReadText
                }
                event.flags = []
                event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
                event.setIntegerValueField(.eventSourceUserData, value: TextLookupTargetAccess.syntheticEventTag)
                event.post(tap: .cghidEventTap)
            }
        }
        // A fresh selection must belong to this text element and cover the clicked position.
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(60))
            let current = try TextLookupTargetAccess.validate(request)
            guard CFEqual(current.element, target.element),
                  hypot(NSEvent.mouseLocation.x - point.x, NSEvent.mouseLocation.y - point.y) <= 4 else { throw CancellationError() }
            let app = AXUIElementCreateApplication(request.targetApplicationPID)
            guard let focused = TextLookupTargetAccess.element(TextLookupTargetAccess.value(app, "AXFocusedUIElement")),
                  CFEqual(focused, target.element),
                  let range = TextLookupTargetAccess.selectedRange(focused),
                  Self.isFreshSelection(range, previous: originalRange,
                      bounds: TextLookupTargetAccess.bounds(range, in: focused), point: axPoint) else { continue }
            let selectionRequest = TextCaptureRequest(id: request.id, intent: .currentSelection,
                targetApplicationPID: request.targetApplicationPID, excludedApplicationPIDs: request.excludedApplicationPIDs,
                primaryScreenMaxY: request.primaryScreenMaxY, triggerAnchorPoint: point)
            do {
                return try await capturer.capture(selectionRequest)
            } catch let error as TextCaptureError {
                guard error.allowsClipboardFallback, allowClipboard else {
                    if error.allowsCompatibilityFallback { return nil }
                    throw error
                }
                _ = try TextLookupTargetAccess.validate(request)
                guard TextLookupTargetAccess.selectedRange(focused) == range else { return nil }
                return try await clipboard.capture(selectionRequest)
            }
        }
        return nil
    }

    nonisolated static func isFreshSelection(_ range: NSRange, previous: NSRange?, bounds: CGRect?, point: CGPoint) -> Bool {
        range.length > 0 && range != previous && bounds?.contains(point) == true
    }
}

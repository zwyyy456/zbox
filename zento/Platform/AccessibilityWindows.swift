import AppKit
import ApplicationServices

/// Shared AX operations; callers own selection and layout policy.
@MainActor
enum AccessibilityWindows {
    static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func frame(of window: AXUIElement) throws -> CGRect {
        guard let positionValue = attribute(kAXPositionAttribute, of: window),
              let sizeValue = attribute(kAXSizeAttribute, of: window),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw AccessibilityWindowError.unableToReadFrame
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else {
            throw AccessibilityWindowError.unableToReadFrame
        }
        return CGRect(origin: point, size: size)
    }

    static func setFrame(_ frame: CGRect, of window: AXUIElement) throws {
        var point = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point),
              let dimensions = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success,
              AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) == .success else {
            throw AccessibilityWindowError.unableToSetFrame
        }
    }

    static func isSettable(_ attribute: String, of window: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, attribute as CFString, &settable) == .success
            && settable.boolValue
    }
}

import AppKit
import ApplicationServices

/// Reads only the known lookup window's accessibility identifier and bounds.
@MainActor
enum FlashDictLookupWindowAccess {
    static func containsMouse() -> Bool {
        let point = NSEvent.mouseLocation
        guard let maxY = NSScreen.screens.first?.frame.maxY else { return false }
        let axPoint = CGPoint(x: point.x, y: maxY - point.y)
        for app in NSWorkspace.shared.runningApplications where
            app.bundleIdentifier == "tech.hyperseek.flashdict" || app.bundleIdentifier == "tech.hyperseek.flashdict.dev" {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            guard let windows = attribute(root, "AXWindows") as? [AXUIElement] else { continue }
            for window in windows where attribute(window, "AXIdentifier") as? String == "flashdict.contextual-lookup" {
                guard let rawPosition = attribute(window, "AXPosition"), CFGetTypeID(rawPosition) == AXValueGetTypeID(),
                      let rawSize = attribute(window, "AXSize"), CFGetTypeID(rawSize) == AXValueGetTypeID() else { continue }
                var position = CGPoint.zero, size = CGSize.zero
                guard AXValueGetValue(unsafeDowncast(rawPosition, to: AXValue.self), .cgPoint, &position),
                      AXValueGetValue(unsafeDowncast(rawSize, to: AXValue.self), .cgSize, &size) else { continue }
                if CGRect(origin: position, size: size).contains(axPoint) { return true }
            }
        }
        return false
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}

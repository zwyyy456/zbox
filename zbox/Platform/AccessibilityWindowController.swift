import AppKit
import ApplicationServices

nonisolated enum WindowAction: Sendable {
    case leftHalf
    case rightHalf
    case maximize
}

nonisolated enum AccessibilityWindowError: LocalizedError, Equatable {
    case permissionRequired
    case noTargetApplication
    case noFocusedWindow
    case unableToReadFrame
    case unableToSetFrame
    case noScreen

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Accessibility permission is required to move windows."
        case .noTargetApplication:
            "The application that owned the window is no longer available."
        case .noFocusedWindow:
            "The target application has no focused window."
        case .unableToReadFrame:
            "The target window position or size could not be read."
        case .unableToSetFrame:
            "The target window does not support this operation."
        case .noScreen:
            "The target window is not on an available display."
        }
    }
}

@MainActor
final class AccessibilityWindowController {
    private let authorization: AccessibilityAuthorization

    init(authorization: AccessibilityAuthorization = AccessibilityAuthorization()) {
        self.authorization = authorization
    }

    func requestPermission() {
        authorization.request()
    }

    func openSystemSettings() {
        authorization.openSystemSettings()
    }

    func perform(_ action: WindowAction, targetPID: pid_t?) throws {
        guard authorization.isTrusted else {
            throw AccessibilityWindowError.permissionRequired
        }
        guard let targetPID,
              NSRunningApplication(processIdentifier: targetPID) != nil else {
            throw AccessibilityWindowError.noTargetApplication
        }

        let application = AXUIElementCreateApplication(targetPID)
        let window = try focusedWindow(of: application)
        let currentAXFrame = try frame(of: window)
        let primaryMaxY = try primaryScreenMaxY()
        let currentCocoaFrame = WindowGeometry.cocoaRect(
            fromAXRect: currentAXFrame,
            primaryScreenMaxY: primaryMaxY
        )
        let screens = NSScreen.screens
        guard let screenIndex = WindowGeometry.screenIndex(
            containing: currentCocoaFrame,
            screenFrames: screens.map(\.frame)
        ), screens.indices.contains(screenIndex) else {
            throw AccessibilityWindowError.noScreen
        }
        let screen = screens[screenIndex]

        let targetCocoaFrame = WindowGeometry.targetRect(for: action, in: screen.visibleFrame)
        let targetAXFrame = WindowGeometry.axRect(
            fromCocoaRect: targetCocoaFrame,
            primaryScreenMaxY: primaryMaxY
        )
        try setFrame(targetAXFrame, of: window)
    }

    private func focusedWindow(of application: AXUIElement) throws -> AXUIElement {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            throw AccessibilityWindowError.noFocusedWindow
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func frame(of window: AXUIElement) throws -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue else {
            throw AccessibilityWindowError.unableToReadFrame
        }

        let axPosition = unsafeDowncast(positionValue, to: AXValue.self)
        let axSize = unsafeDowncast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(axPosition, .cgPoint, &position),
              AXValueGetValue(axSize, .cgSize, &size) else {
            throw AccessibilityWindowError.unableToReadFrame
        }

        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, of window: AXUIElement) throws {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(
                window,
                kAXPositionAttribute as CFString,
                positionValue
              ) == .success,
              AXUIElementSetAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                sizeValue
              ) == .success else {
            throw AccessibilityWindowError.unableToSetFrame
        }
    }

    private func primaryScreenMaxY() throws -> CGFloat {
        guard let primary = NSScreen.screens.first else {
            throw AccessibilityWindowError.noScreen
        }
        return primary.frame.maxY
    }
}

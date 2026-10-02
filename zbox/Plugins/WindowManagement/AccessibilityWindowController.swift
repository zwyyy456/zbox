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
            String(localized: "Accessibility permission is required to move windows.")
        case .noTargetApplication:
            String(localized: "The application that owned the window is no longer available.")
        case .noFocusedWindow:
            String(localized: "The target application has no focused window.")
        case .unableToReadFrame:
            String(localized: "The target window position or size could not be read.")
        case .unableToSetFrame:
            String(localized: "The target window does not support this operation.")
        case .noScreen:
            String(localized: "The target window is not on an available display.")
        }
    }
}

@MainActor
final class AccessibilityWindowController {
    private let authorization: AccessibilityAuthorization

    init(authorization: AccessibilityAuthorization = AccessibilityAuthorization()) {
        self.authorization = authorization
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
        let currentAXFrame = try AccessibilityWindows.frame(of: window)
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
        try AccessibilityWindows.setFrame(targetAXFrame, of: window)
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

    private func primaryScreenMaxY() throws -> CGFloat {
        guard let primary = NSScreen.screens.first else {
            throw AccessibilityWindowError.noScreen
        }
        return primary.frame.maxY
    }
}

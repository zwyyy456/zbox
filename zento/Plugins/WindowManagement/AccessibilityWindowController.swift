import AppKit
import ApplicationServices

nonisolated enum WindowAction: Sendable {
    case leftHalf
    case rightHalf
    case maximize
    case topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case center, restore, previousDisplay, nextDisplay
}

nonisolated enum AccessibilityWindowError: LocalizedError, Equatable {
    case permissionRequired
    case noTargetApplication
    case noFocusedWindow
    case unableToReadFrame
    case unableToSetFrame
    case noScreen
    case nothingToRestore, restoreDisplayUnavailable, noOtherDisplay

    var errorDescription: String? {
        switch self {
        case .nothingToRestore: String(localized: "There is no previous position to restore for this window.")
        case .restoreDisplayUnavailable: String(localized: "The display used by the previous window position is no longer connected.")
        case .noOtherDisplay: String(localized: "Connect another display to move this window between displays.")
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
    private struct PreviousFrame {
        let window: AXUIElement
        let frame: CGRect
        let displayID: NSNumber
    }
    private var previousFrames: [PreviousFrame] = []

    func clearHistory() { previousFrames.removeAll() }

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
        // Stable spatial order: left to right, then top to bottom for vertical stacks.
        let screens = NSScreen.screens.sorted {
            $0.frame.minX == $1.frame.minX ? $0.frame.maxY > $1.frame.maxY : $0.frame.minX < $1.frame.minX
        }
        guard let screenIndex = WindowGeometry.screenIndex(
            containing: currentCocoaFrame,
            screenFrames: screens.map(\.frame)
        ), screens.indices.contains(screenIndex) else {
            throw AccessibilityWindowError.noScreen
        }
        let screen = screens[screenIndex]

        previousFrames.removeAll { (try? AccessibilityWindows.frame(of: $0.window)) == nil }
        let previousIndex = previousFrames.firstIndex { CFEqual($0.window, window) }
        let targetCocoaFrame: CGRect
        switch action {
        case .restore:
            guard let previousIndex else { throw AccessibilityWindowError.nothingToRestore }
            let saved = previousFrames[previousIndex]
            guard let originalScreen = screens.first(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == saved.displayID }) else {
                throw AccessibilityWindowError.restoreDisplayUnavailable
            }
            targetCocoaFrame = WindowGeometry.fitting(saved.frame, in: originalScreen.visibleFrame)
        case .previousDisplay, .nextDisplay:
            guard screens.count > 1 else { throw AccessibilityWindowError.noOtherDisplay }
            let index = (screenIndex + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count
            targetCocoaFrame = WindowGeometry.moving(currentCocoaFrame, from: screen.visibleFrame, to: screens[index].visibleFrame)
        default:
            guard let frame = WindowGeometry.targetRect(for: action, in: screen.visibleFrame, currentFrame: currentCocoaFrame) else {
                throw AccessibilityWindowError.unableToSetFrame
            }
            targetCocoaFrame = frame
        }
        guard targetCocoaFrame != currentCocoaFrame else {
            if action == .restore, let previousIndex { previousFrames.remove(at: previousIndex) }
            return
        }
        guard AccessibilityWindows.isSettable(kAXPositionAttribute, of: window),
              AccessibilityWindows.isSettable(kAXSizeAttribute, of: window) else {
            throw AccessibilityWindowError.unableToSetFrame
        }
        if action != .restore {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                throw AccessibilityWindowError.noScreen
            }
            // Save before AX writes: an app can accept the position but reject the size.
            if let previousIndex { previousFrames.remove(at: previousIndex) }
            previousFrames.append(PreviousFrame(window: window, frame: currentCocoaFrame, displayID: displayID))
        }
        let targetAXFrame = WindowGeometry.axRect(
            fromCocoaRect: targetCocoaFrame,
            primaryScreenMaxY: primaryMaxY
        )
        try AccessibilityWindows.setFrame(targetAXFrame, of: window)
        // Reapply position after resizing; some apps constrain the first move using the old size.
        var origin = targetAXFrame.origin
        guard let value = AXValueCreate(.cgPoint, &origin),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success else {
            throw AccessibilityWindowError.unableToSetFrame
        }
        if action == .restore, let previousIndex { previousFrames.remove(at: previousIndex) }
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

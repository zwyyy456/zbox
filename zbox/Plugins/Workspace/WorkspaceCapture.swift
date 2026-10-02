import AppKit
import ApplicationServices

nonisolated struct WorkspaceDisplay: Identifiable {
    let id: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect

    static func matching(_ id: String, in displays: [WorkspaceDisplay]) -> WorkspaceDisplay? {
        let matches = displays.filter { $0.id == id }
        return matches.count == 1 ? matches.first : nil
    }

    @MainActor static func current() -> [WorkspaceDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
            return WorkspaceDisplay(id: CFUUIDCreateString(nil, uuid) as String,
                                    name: screen.localizedName, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }
}

struct WorkspaceCaptureWindow: Identifiable {
    let id = UUID()
    let title: String
    let entry: WorkspaceEntry
}

struct WorkspaceCaptureApplication: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let windows: [WorkspaceCaptureWindow]
}

struct WorkspaceCapture: Identifiable {
    let id = UUID()
    let replacing: WorkspaceLayout?
    let applications: [WorkspaceCaptureApplication]
    let notices: [String]
}

@MainActor
enum WorkspaceWindowAccess {
    static func windows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return AccessibilityWindows.attribute(kAXWindowsAttribute, of: app) as? [AXUIElement] ?? []
    }

    static func exclusion(of window: AXUIElement, pid: pid_t) -> String? {
        guard AccessibilityWindows.attribute(kAXSubroleAttribute, of: window) as? String == kAXStandardWindowSubrole else {
            return String(localized: "Not a standard window")
        }
        if AccessibilityWindows.attribute(kAXMinimizedAttribute, of: window) as? Bool == true {
            return String(localized: "Window is minimized")
        }
        if AccessibilityWindows.attribute("AXFullScreen", of: window) as? Bool == true {
            return String(localized: "Window is full screen")
        }
        guard AccessibilityWindows.isSettable(kAXPositionAttribute, of: window),
              AccessibilityWindows.isSettable(kAXSizeAttribute, of: window) else {
            return String(localized: "Window cannot be resized")
        }
        guard let frame = try? AccessibilityWindows.frame(of: window), frame.width > 0, frame.height > 0 else {
            return String(localized: "Window frame is unavailable")
        }
        // Only metadata is needed; do not request screen capture or read window contents.
        let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let isVisible = visible.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return abs(rect.minX - frame.minX) < 2 && abs(rect.minY - frame.minY) < 2
                && abs(rect.width - frame.width) < 2 && abs(rect.height - frame.height) < 2
        }
        return isVisible ? nil : String(localized: "Window is hidden or on another desktop")
    }

    static func capture(replacing: WorkspaceLayout? = nil) throws -> WorkspaceCapture {
        guard AXIsProcessTrusted() else { throw AccessibilityWindowError.permissionRequired }
        let displays = WorkspaceDisplay.current()
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { throw AccessibilityWindowError.noScreen }
        var applications: [WorkspaceCaptureApplication] = []
        var notices: [String] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundleID = app.bundleIdentifier, let url = app.bundleURL else { continue }
            let name = app.localizedName ?? bundleID
            var candidates: [WorkspaceCaptureWindow] = []
            for window in windows(for: app.processIdentifier) {
                if let reason = exclusion(of: window, pid: app.processIdentifier) {
                    notices.append("\(name): \(reason)")
                    continue
                }
                let axFrame = try AccessibilityWindows.frame(of: window)
                let frame = WindowGeometry.cocoaRect(fromAXRect: axFrame, primaryScreenMaxY: primaryMaxY)
                guard let index = WindowGeometry.screenIndex(containing: frame, screenFrames: displays.map(\.frame)) else { continue }
                let display = displays[index]
                let title = AccessibilityWindows.attribute(kAXTitleAttribute, of: window) as? String ?? name
                candidates.append(WorkspaceCaptureWindow(title: title.isEmpty ? name : title,
                    entry: WorkspaceEntry(bundleID: bundleID, applicationName: name, applicationURL: url,
                        displayID: display.id, displayName: display.name,
                        frame: WorkspaceGeometry.normalized(frame, in: display.visibleFrame))))
            }
            if !candidates.isEmpty {
                applications.append(WorkspaceCaptureApplication(bundleID: bundleID, name: name, windows: candidates))
            }
        }
        return WorkspaceCapture(replacing: replacing,
            applications: applications.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            notices: Array(Set(notices)).sorted())
    }
}

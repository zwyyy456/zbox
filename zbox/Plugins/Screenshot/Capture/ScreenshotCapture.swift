import AppKit
import ScreenCaptureKit

nonisolated enum ScreenshotMode: String, CaseIterable {
    case area, window, screen
    var commandID: CommandID { CommandID("screenshot.\(rawValue)") }
    var title: String {
        switch self {
        case .area: String(localized: "Capture Area")
        case .window: String(localized: "Capture Window")
        case .screen: String(localized: "Capture Screen")
        }
    }
}

nonisolated enum ScreenshotError: LocalizedError {
    case permission, unavailable, captureFailed, exportFailed
    var errorDescription: String? {
        switch self {
        case .permission: String(localized: "Allow Screen Recording in System Settings, then try the screenshot again.")
        case .unavailable: String(localized: "The selected screen or window is no longer available.")
        case .captureFailed: String(localized: "The screenshot could not be captured. Try again.")
        case .exportFailed: String(localized: "The screenshot could not be exported.")
        }
    }
}

nonisolated enum ScreenshotGeometry {
    static func screenRect(_ cocoaRect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cocoaRect.minX, y: primaryHeight - cocoaRect.maxY,
               width: cocoaRect.width, height: cocoaRect.height)
    }

    static func sourceRect(_ selection: CGRect, in screen: CGRect) -> CGRect {
        let clipped = selection.intersection(screen)
        return CGRect(x: clipped.minX - screen.minX, y: screen.maxY - clipped.maxY,
                      width: clipped.width, height: clipped.height)
    }
}

@MainActor
enum ScreenshotCapture {
    static func content() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenshotError.permission
        }
        return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    static func image(content: SCShareableContent, screen: NSScreen,
                      area: CGRect? = nil, window: SCWindow? = nil) async throws -> CGImage {
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        if let window {
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
            config.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        } else {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw ScreenshotError.unavailable
            }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            guard area == nil || !ownApps.isEmpty else { throw ScreenshotError.captureFailed }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let rect = ScreenshotGeometry.sourceRect(area ?? screen.frame, in: screen.frame)
            config.sourceRect = rect
            config.width = Int((rect.width * CGFloat(filter.pointPixelScale)).rounded())
            config.height = Int((rect.height * CGFloat(filter.pointPixelScale)).rounded())
        }
        try Task.checkCancellation()
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

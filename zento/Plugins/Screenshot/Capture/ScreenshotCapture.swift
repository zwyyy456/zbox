import AppKit
import ScreenCaptureKit

nonisolated enum ScreenshotMode: String, CaseIterable {
    case area, window, screen, scrolling
    var commandID: CommandID { CommandID("screenshot.\(rawValue)") }
    var title: String {
        switch self {
        case .scrolling: String(localized: "Capture Scrolling Area")
        case .area: String(localized: "Capture Area")
        case .window: String(localized: "Capture Window")
        case .screen: String(localized: "Capture Screen")
        }
    }
}

nonisolated enum ScreenshotError: LocalizedError {
    case permission, unavailable, captureFailed, exportFailed, pinLimit, clipboardImage
    var errorDescription: String? {
        switch self {
        case .clipboardImage: String(localized: "Copy a single PNG or TIFF image first. Clipboard access must be allowed; private or transient contents cannot be pinned.")
        case .pinLimit: String(localized: "Close some pinned images before adding another (10 images / 256 MiB maximum).")
        case .permission: String(localized: "Allow Screen Recording in System Settings, then try again.")
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

    static func snapshotPixelRect(_ selection: CGRect, in screen: CGRect, pixels: CGSize) -> CGRect {
        let rect = sourceRect(selection, in: screen)
        let scaleX = pixels.width / screen.width, scaleY = pixels.height / screen.height
        let left = (rect.minX * scaleX).rounded(), top = (rect.minY * scaleY).rounded()
        return CGRect(x: left, y: top, width: (rect.maxX * scaleX).rounded() - left,
                      height: (rect.maxY * scaleY).rounded() - top)
    }

    // Window Server metadata is refreshed when hit-testing; SCWindow objects are only capture identities.
    static func selectableWindowFrames(_ info: [[String: Any]]) -> [(CGWindowID, CGRect)] {
        info.compactMap { row in
            guard let id = row[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  let alpha = row[kCGWindowAlpha as String] as? Double,
                  let sharing = row[kCGWindowSharingState as String] as? Int,
                  row[kCGWindowIsOnscreen as String] as? Bool == true,
                  isSelectableWindow(frame: frame, alpha: alpha, sharingState: sharing) else { return nil }
            return (id, frame)
        }
    }

    static func isSelectableWindow(frame: CGRect, alpha: Double, sharingState: Int) -> Bool {
        frame.width > 0 && frame.height > 0 && !frame.isInfinite && !frame.isNull
            && alpha > 0 && sharingState != 0
    }

    static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let left = ceil(rect.minX * scale), top = ceil(rect.minY * scale)
        return CGRect(x: left / scale, y: top / scale,
                      width: max(0, floor(rect.maxX * scale) - left) / scale,
                      height: max(0, floor(rect.maxY * scale) - top) / scale)
    }

    static func sourceRect(_ selection: CGRect, in screen: CGRect) -> CGRect {
        let clipped = selection.intersection(screen)
        return CGRect(x: clipped.minX - screen.minX, y: screen.maxY - clipped.maxY,
                      width: clipped.width, height: clipped.height)
    }
}

@MainActor
enum ScreenshotCapture {
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func snapshots(content: SCShareableContent, screens: [NSScreen]) async throws -> [CGDirectDisplayID: CGImage] {
        var result: [CGDirectDisplayID: CGImage] = [:]
        for screen in screens {
            guard let id = displayID(for: screen) else { throw ScreenshotError.unavailable }
            result[id] = try await image(content: content, screen: screen)
        }
        return result
    }

    static func crop(_ snapshot: CGImage, area: CGRect, screenFrame: CGRect) throws -> CGImage {
        let rect = ScreenshotGeometry.snapshotPixelRect(area, in: screenFrame,
                                                        pixels: CGSize(width: snapshot.width, height: snapshot.height))
        guard rect.width > 0, rect.height > 0, let image = snapshot.cropping(to: rect) else {
            throw ScreenshotError.unavailable
        }
        return image
    }

    static func content() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenshotError.permission
        }
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func image(content: SCShareableContent, screen: NSScreen,
                      area: CGRect? = nil, alignToPixels: Bool = false) async throws -> CGImage {
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.showsCursor = false
        let displayID = displayID(for: screen)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotError.unavailable
        }
        filter = SCContentFilter(display: display, excludingWindows: [])
        var rect = ScreenshotGeometry.sourceRect(area ?? screen.frame, in: screen.frame)
        if alignToPixels {
            rect = ScreenshotGeometry.pixelAligned(rect, scale: CGFloat(filter.pointPixelScale))
        }
        config.sourceRect = rect
        config.width = Int((rect.width * CGFloat(filter.pointPixelScale)).rounded())
        config.height = Int((rect.height * CGFloat(filter.pointPixelScale)).rounded())
        try Task.checkCancellation()
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

import AppKit
import ImageIO

@MainActor
enum ScreenshotPinClipboard {
    static func read(from board: NSPasteboard = .general) throws -> Data {
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny { throw ScreenshotError.clipboardImage }
        let count = board.changeCount
        let types = Set((board.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: ClipboardContentPolicy.ignoredTypes),
              !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue),
              board.pasteboardItems?.count == 1 else { throw ScreenshotError.clipboardImage }
        guard let data = board.data(forType: .png) ?? board.data(forType: .tiff), count == board.changeCount else {
            throw ScreenshotError.clipboardImage
        }
        guard data.count <= 32 * 1_024 * 1_024 else { throw ScreenshotError.pinLimit }
        return data
    }

    @concurrent static func decode(_ data: Data) async throws -> CGImage {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else {
            throw ScreenshotError.clipboardImage
        }
        guard width <= 64_000_000 / height else { throw ScreenshotError.pinLimit }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { throw ScreenshotError.clipboardImage }
        try Task.checkCancellation()
        return image
    }
}

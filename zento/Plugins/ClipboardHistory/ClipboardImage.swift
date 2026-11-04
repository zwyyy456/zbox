import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ClipboardImage {
    static let byteLimit = 10 * 1_024 * 1_024
    static let pixelLimit = 20_000_000

    static func dimensions(of data: Data) throws -> (Int, Int) {
        guard data.count <= byteLimit else { throw ClipboardHistoryError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ClipboardHistoryError.unsupported }
        guard width <= pixelLimit / height else { throw ClipboardHistoryError.tooLarge }
        return (width, height)
    }

    static func canPreviewFile(_ url: URL) -> Bool {
        url.isFileURL && UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    @concurrent
    static func fileThumbnail(_ url: URL, maxPixelSize: Int = 640) async throws -> Data {
        try Task.checkCancellation()
        guard canPreviewFile(url) else { throw ClipboardHistoryError.unsupported }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ClipboardHistoryError.unsupported }
        guard let size = values.fileSize, size <= byteLimit else { throw ClipboardHistoryError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Bound the read even if the referenced file grows after the metadata check.
        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        try Task.checkCancellation()
        return try await thumbnail(data, maxPixelSize: maxPixelSize)
    }

    @concurrent
    static func thumbnail(_ data: Data, maxPixelSize: Int = 640) async throws -> Data {
        _ = try dimensions(of: data)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { throw ClipboardHistoryError.unsupported }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ClipboardHistoryError.unsupported
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ClipboardHistoryError.unsupported }
        return output as Data
    }
}

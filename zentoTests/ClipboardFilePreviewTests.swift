import AppKit
import Testing
@testable import zento

@MainActor
struct ClipboardFilePreviewTests {
    @Test
    func jpegPreviewPreservesFileReferenceAndOriginalBytes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let representation = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: 32, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 3,
            hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 96, bitsPerPixel: 24))
        representation.bitmapData?.initialize(repeating: 120, count: representation.bytesPerRow * representation.pixelsHigh)
        let original = try #require(representation.representation(using: .jpeg, properties: [:]))
        try original.write(to: url)
        let payload = ClipboardPayload(kind: "files", text: url.path,
            data: try ClipboardFileReferences.encode([url]), sourceBundleID: nil)

        let thumbnail = try await ClipboardImage.fileThumbnail(url, maxPixelSize: 8)
        let dimensions = try ClipboardImage.dimensions(of: thumbnail)
        #expect(dimensions.0 == 8 && dimensions.1 == 4)
        #expect(try Data(contentsOf: url) == original)
        #expect(try ClipboardFileReferences.decode(payload.data) == [url])

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try ClipboardWriter.write(payload, to: board, coordinator: ClipboardAccessCoordinator())
        #expect(board.string(forType: .fileURL).flatMap(URL.init(string:)) == url)
        #expect(board.data(forType: .png) == nil)
    }

    @Test(arguments: [false, true])
    func rejectsCorruptAndOversizedReferencedImages(oversized: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)
        if oversized {
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(ClipboardImage.byteLimit + 1))
            try handle.close()
        }
        let expected: ClipboardHistoryError = oversized ? .tooLarge : .unsupported
        await #expect(throws: expected) {
            _ = try await ClipboardImage.fileThumbnail(url)
        }
    }

    @Test
    func missingReferenceCannotProducePreview() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        await #expect(throws: (any Error).self) {
            _ = try await ClipboardImage.fileThumbnail(url)
        }
    }
}

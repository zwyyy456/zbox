import Foundation
import Testing
@testable import zento

struct ScreenshotAutomaticSaveTests {
    @Test func savesDistinctFilesInChosenDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = Data([1, 2, 3])
        let first = try await ScreenshotAutomaticSave.write(data, format: .png, directory: directory)
        let second = try await ScreenshotAutomaticSave.write(data, format: .png, directory: directory)
        #expect(first != second)
        #expect(first.deletingLastPathComponent().path == directory.path)
        #expect(first.pathExtension == "png")
        #expect(try Data(contentsOf: first) == data)
        #expect(try Data(contentsOf: second) == data)
    }

    @Test func missingDirectoryFailsWithoutCreatingIt() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await #expect(throws: (any Error).self) {
            try await ScreenshotAutomaticSave.write(Data([1]), format: .jpeg, directory: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

import AVFoundation
import Darwin
import Foundation

nonisolated enum RecordingFiles {
    private static var root: URL {
        FileManager.default.temporaryDirectory.appending(path: "tech.hyperseek.zento.recordings", directoryHint: .isDirectory)
    }

    @concurrent static func removeAbandonedSessions() async throws {
        let directories: [URL]
        do {
            directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }
        for directory in directories {
            guard let owner = pid_t(directory.lastPathComponent), owner > 0 else { continue }
            // Another launched instance or a test host can share the temp root.
            if owner == getpid() || (kill(owner, 0) == -1 && errno == ESRCH) {
                try removeIfPresent(directory)
            }
        }
    }

    @concurrent static func makeSessionDirectory() async throws -> URL {
        let directory = root.appending(path: String(getpid()), directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    @concurrent static func removeSession(_ directory: URL) async throws {
        try removeIfPresent(directory)
    }

    private static func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
    }

    @concurrent static func save(_ source: URL, to destination: URL, replaceExisting: Bool) async throws {
        let manager = FileManager.default
        // Stage the full copy on the destination volume before committing the save.
        let staging = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                      appropriateFor: destination, create: true)
        defer { try? manager.removeItem(at: staging) }
        let copy = staging.appending(path: source.lastPathComponent)
        try manager.copyItem(at: source, to: copy)
        if replaceExisting {
            _ = try manager.replaceItemAt(destination, withItemAt: copy)
        } else {
            try manager.moveItem(at: copy, to: destination)
        }
    }

    @concurrent static func validateVideo(_ url: URL, size: CGSize) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), try await asset.load(.duration).seconds > 0,
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingError.emptyVideo
        }
        let dimensions = try await track.load(.naturalSize)
        guard dimensions == size else { throw RecordingError.unexpectedSize }
    }
}

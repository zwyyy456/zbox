import AppKit

/// Stores locations only, never the contents of files or directories.
nonisolated enum ClipboardFileReferences {
    static func encode(_ urls: [URL]) throws -> Data {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { throw ClipboardHistoryError.unsupported }
        let data = try JSONEncoder().encode(urls)
        guard data.count <= ClipboardReader.textLimit else { throw ClipboardHistoryError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> [URL] {
        let urls = try JSONDecoder().decode([URL].self, from: data)
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { throw ClipboardHistoryError.unsupported }
        return urls
    }
}

@MainActor
enum ClipboardWriter {
    static func write(_ payload: ClipboardPayload, to board: NSPasteboard,
                      coordinator: ClipboardAccessCoordinator) throws {
        var files: [URL] = []
        if payload.kind == "files" {
            files = try ClipboardFileReferences.decode(payload.data)
            guard files.allSatisfy({ (try? $0.checkResourceIsReachable()) == true }) else {
                throw ClipboardHistoryError.fileUnavailable
            }
        }
        // Validate the entire reference group before replacing the current clipboard.
        board.prepareForNewContents(with: .currentHostOnly)
        defer { coordinator.didWrite(changeCount: board.changeCount) }
        let copied: Bool
        switch payload.kind {
        case "files": copied = board.writeObjects(files.map { $0 as NSURL })
        case "png", "tiff": copied = board.setData(payload.data, forType: payload.kind == "png" ? .png : .tiff)
        default: copied = board.setString(payload.text, forType: .string)
        }
        guard copied else { throw ClipboardHistoryError.unsupported }
    }
}

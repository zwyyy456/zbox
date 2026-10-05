import Foundation
import zlib

/// Reads the ordinary ZIP subset used by extension packages. Never delegates extraction of untrusted paths.
nonisolated enum ExtensionArchive {
    static let sizeLimit = 128 * 1024 * 1024
    static let fileLimit = 4096

    static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ExtensionFailure("The package contains an unsafe path.")
        }
    }

    static func copyDirectory(_ source: URL, to destination: URL) throws {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var enumerationError: Error?
        guard let entries = FileManager.default.enumerator(at: source, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
            enumerationError = error; return false
        }) else { throw ExtensionFailure("Cannot read the extension directory.") }
        var total = 0, count = 0
        for case let file as URL in entries {
            count += 1
            let info = try file.resourceValues(forKeys: keys)
            guard count <= fileLimit, info.isSymbolicLink != true, info.isDirectory == true || info.isRegularFile == true else {
                throw ExtensionFailure("Packages must contain only ordinary files and directories.")
            }
            let base = source.resolvingSymlinksInPath().path
            let canonical = file.resolvingSymlinksInPath().path
            guard canonical.hasPrefix(base + "/") else { throw ExtensionFailure("The package entry escaped its directory.") }
            let path = String(canonical.dropFirst(base.count + 1))
            try validatePath(path)
            let target = destination.appending(path: path)
            if info.isDirectory == true { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                total += info.fileSize ?? 0
                guard total <= sizeLimit else { throw ExtensionFailure("The package exceeds 128 MiB.") }
                try FileManager.default.copyItem(at: file, to: target)
            }
        }
        if let enumerationError { throw enumerationError }
    }

    static func extract(_ source: URL, to destination: URL) throws {
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: sizeLimit + 1) ?? Data()
        guard data.count >= 22, data.count <= sizeLimit else { throw ExtensionFailure("Invalid or oversized ZIP package.") }
        func number(_ offset: Int, _ width: Int) throws -> Int {
            guard offset >= 0, offset + width <= data.count else { throw ExtensionFailure("Truncated ZIP package.") }
            return (0..<width).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        guard let end = try stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1).first(where: {
            try number($0, 4) == 0x06054b50 && $0 + 22 + number($0 + 20, 2) == data.count
        }) else { throw ExtensionFailure("Unsupported ZIP package.") }
        let count = try number(end + 10, 2)
        guard try number(end + 4, 2) == 0, try number(end + 6, 2) == 0,
              try number(end + 8, 2) == count, count <= fileLimit else { throw ExtensionFailure("Split or oversized ZIP packages are unsupported.") }
        var cursor = try number(end + 16, 4)
        let centralEnd = cursor + (try number(end + 12, 4))
        guard centralEnd <= end else { throw ExtensionFailure("Invalid ZIP directory.") }
        var paths = Set<String>(), total = 0
        for _ in 0..<count {
            guard try number(cursor, 4) == 0x02014b50 else { throw ExtensionFailure("Invalid ZIP directory.") }
            let flags = try number(cursor + 8, 2), method = try number(cursor + 10, 2)
            let packed = try number(cursor + 20, 4), size = try number(cursor + 24, 4)
            let nameLength = try number(cursor + 28, 2), extra = try number(cursor + 30, 2), comment = try number(cursor + 32, 2)
            let attributes = try number(cursor + 38, 4), local = try number(cursor + 42, 4)
            let next = cursor + 46 + nameLength + extra + comment
            guard next <= centralEnd, flags & 1 == 0, [0, 8].contains(method),
                  let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8) else {
                throw ExtensionFailure("Encrypted or unsupported ZIP entry.")
            }
            let directory = name.hasSuffix("/")
            let path = directory ? String(name.dropLast()) : name
            try validatePath(path)
            let kind = (attributes >> 16) & 0xf000
            guard [0, 0x8000, 0x4000].contains(kind),
                  paths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw ExtensionFailure("ZIP links, special files and duplicate paths are not supported.")
            }
            total += size
            guard total <= sizeLimit else { throw ExtensionFailure("The package exceeds 128 MiB.") }
            guard try number(local, 4) == 0x04034b50, try number(local + 8, 2) == method,
                  try number(local + 26, 2) == nameLength else { throw ExtensionFailure("Invalid ZIP entry header.") }
            let start = local + 30 + nameLength + (try number(local + 28, 2))
            guard start <= data.count, start + packed <= data.count,
                  data.subdata(in: local + 30..<local + 30 + nameLength) == data.subdata(in: cursor + 46..<cursor + 46 + nameLength) else {
                throw ExtensionFailure("Invalid ZIP entry bounds.")
            }
            let target = destination.appending(path: path)
            if directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                let input = data.subdata(in: start..<start + packed)
                let output = try method == 0 ? input : inflateData(input, size: size)
                let checksum = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(output.count)) }
                guard output.count == size, checksum == (try number(cursor + 16, 4)) else { throw ExtensionFailure("ZIP content verification failed.") }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try output.write(to: target, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: attributes >> 16 & 0o111 != 0 ? 0o700 : 0o600], ofItemAtPath: target.path)
            }
            cursor = next
        }
        guard cursor == centralEnd else { throw ExtensionFailure("Invalid ZIP directory size.") }
        // Retain download provenance instead of stripping quarantine during extraction.
        var quarantine = [UInt8](repeating: 0, count: 4096)
        let length = getxattr(source.path, "com.apple.quarantine", &quarantine, quarantine.count, 0, 0)
        if length > 0, let entries = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil) {
            for case let file as URL in entries {
                guard setxattr(file.path, "com.apple.quarantine", quarantine, length, 0, 0) == 0 else {
                    throw ExtensionFailure("Could not preserve package download provenance.")
                }
            }
        }
    }

    private static func inflateData(_ input: Data, size: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ExtensionFailure("Cannot decode ZIP entry.")
        }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(1, size))
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(max(1, size))
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == size, stream.total_in == input.count else {
            throw ExtensionFailure("Invalid compressed ZIP content.")
        }
        output.count = size
        return output
    }
}

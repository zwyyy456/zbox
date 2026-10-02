import Foundation

/// Only numeric vendor/model IDs and a generated plist cross this privileged boundary.
nonisolated struct DisplayOverrideFile: Sendable {
    let vendor: UInt32
    let product: UInt32
    let data: Data

    var directory: String { "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-\(String(vendor, radix: 16))" }
    var path: String { "\(directory)/DisplayProductID-\(String(product, radix: 16))" }

    func script(removing: Bool) -> String {
        let directories = ["/Library", "/Library/Displays", "/Library/Displays/Contents",
                           "/Library/Displays/Contents/Resources", "/Library/Displays/Contents/Resources/Overrides", directory]
        let create = removing ? "[ -d \"$directory\" ]" : "[ -d \"$directory\" ] || /bin/mkdir \"$directory\""
        let operation = removing
            ? "if [ ! -f \"$target\" ] || [ -L \"$target\" ]; then exit 1; fi\n/usr/bin/cmp -s \"$temporary\" \"$target\"\n/bin/rm \"$target\""
            : "if [ -e \"$target\" ] || [ -L \"$target\" ]; then exit 1; fi\n/bin/ln \"$temporary\" \"$target\""
        return """
        set -eu
        umask 022
        for directory in \(directories.joined(separator: " ")); do
            [ ! -L "$directory" ]
            \(create)
            [ "$(/usr/bin/stat -f %u "$directory")" -eq 0 ]
            mode=$(/usr/bin/stat -f %Lp "$directory")
            [ $((0$mode & 022)) -eq 0 ]
        done
        target='\(path)'
        temporary=$(/usr/bin/mktemp '\(directory)/.zbox-hidpi.XXXXXX')
        trap '/bin/rm -f "$temporary"' EXIT
        /usr/bin/printf '%s' '\(data.base64EncodedString())' | /usr/bin/base64 -D > "$temporary"
        /usr/bin/plutil -lint "$temporary" >/dev/null
        /bin/chmod 644 "$temporary"
        /usr/sbin/chown root:wheel "$temporary"
        \(operation)
        """
    }

    func install() async throws {
        guard !FileManager.default.fileExists(atPath: path) else { throw DisplayHiDPIError.existingOverride }
        try await Self.run(script(removing: false))
        guard try Data(contentsOf: URL(filePath: path)) == data else { throw DisplayHiDPIError.administratorFailed }
    }

    func remove() async throws {
        guard try Data(contentsOf: URL(filePath: path)) == data else { throw DisplayHiDPIError.modifiedOverride }
        try await Self.run(script(removing: true))
        guard !FileManager.default.fileExists(atPath: path) else { throw DisplayHiDPIError.administratorFailed }
    }

    private static func run(_ shellScript: String) async throws {
        // The script is passed as an argument, never interpolated into another shell command.
        let escaped = shellScript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw DisplayHiDPIError.administratorFailed }
        }.value
    }
}

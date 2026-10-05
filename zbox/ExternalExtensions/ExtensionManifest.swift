import Foundation

nonisolated struct ExtensionFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

nonisolated struct ExtensionManifest: Codable, Sendable, Identifiable {
    let schemaVersion: Int
    let id: String
    let name: String
    let version: String
    var author: String?
    var minimumHostVersion: String?
    var minimumSystemVersion: String?
    var architectures: [String]?
    var capabilities: [String]?
    var settings: [ExtensionSetting]?
    let commands: [ExtensionCommand]

    static let supportedCapabilities: Set<String> = ["selection.read", "clipboard.read", "clipboard.write", "clipboard.paste", "storage", "credentials"]

    func validate() throws {
        guard schemaVersion == 1, Self.validID(id), id.contains("."), !name.isEmpty,
              Self.versionParts(version) != nil, version.split(separator: ".").count == 3, !commands.isEmpty, commands.count <= 100,
              Set(commands.map(\.id)).count == commands.count else {
            throw ExtensionFailure("Invalid extension identity, version or commands.")
        }
        guard Set(capabilities ?? []).isSubset(of: Self.supportedCapabilities) else {
            throw ExtensionFailure("This extension requires unsupported host capabilities.")
        }
        let fields = settings ?? []
        guard Set(fields.map(\.id)).count == fields.count else { throw ExtensionFailure("Duplicate setting IDs.") }
        for field in fields { try field.validate() }
        guard !fields.contains(where: { $0.type == "secret" }) || (capabilities ?? []).contains("credentials") else {
            throw ExtensionFailure("Secret settings require the credentials capability.")
        }
        for command in commands { try command.validate() }
    }

    func checkEnvironment() throws {
        let host = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        for (required, actual) in [(minimumHostVersion, host), (minimumSystemVersion, "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")] {
            if let required {
                guard let expected = Self.versionParts(required), let current = Self.versionParts(actual),
                      !current.lexicographicallyPrecedes(expected) else {
                    throw ExtensionFailure("The extension requires a newer host or macOS version.")
                }
            }
        }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        if let architectures, !architectures.contains(architecture) {
            throw ExtensionFailure("The extension does not support this CPU architecture.")
        }
    }

    static func capabilityLabel(_ capability: String) -> String {
        switch capability {
        case "selection.read": String(localized: "Read Selected Text")
        case "clipboard.read": String(localized: "Read Clipboard Text")
        case "clipboard.write": String(localized: "Copy Text")
        case "clipboard.paste": String(localized: "Paste into Original App")
        case "storage": String(localized: "Save Extension Data")
        case "credentials": String(localized: "Store and Read Extension Credentials")
        default: capability
        }
    }

    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 45
        } && !value.split(separator: ".", omittingEmptySubsequences: false).contains("")
    }

    static func versionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return parts.map { Int($0)! } + Array(repeating: 0, count: 3 - parts.count)
    }
}

nonisolated struct ExtensionSetting: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    var type: String = "text"
    var defaultValue: String?
    var options: [String]?
    func validate() throws {
        guard ExtensionManifest.validID(id), !name.isEmpty,
              ["text", "boolean", "choice", "secret"].contains(type),
              type != "choice" || !(options ?? []).isEmpty else { throw ExtensionFailure("Invalid setting declaration.") }
    }
}

nonisolated struct ExtensionParameter: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    var defaultValue: String?
    var required: Bool?
}

nonisolated struct ExtensionCommand: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let mode: String
    let entry: String
    var interpreter: String?
    var keywords: [String]?
    var arguments: [String]?
    var parameters: [ExtensionParameter]?
    var timeout: Double?
    var protocolVersion: Int?

    func commandID(in package: String) -> CommandID { CommandID("extensions.\(package)/\(id)") }

    func validate() throws {
        guard !id.isEmpty, id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              !name.isEmpty, ["task", "interactive"].contains(mode),
              mode != "interactive" || protocolVersion == 1,
              (timeout ?? 60).isFinite, (1...3600).contains(timeout ?? 60),
              !([entry, interpreter ?? ""] + (arguments ?? [])).contains(where: { $0.contains("\0") }),
              (parameters ?? []).allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && !($0.defaultValue ?? "").contains("\0") }),
              Set((parameters ?? []).map(\.id)).count == (parameters ?? []).count else {
            throw ExtensionFailure("Invalid extension command.")
        }
        try ExtensionArchive.validatePath(entry)
    }

    func invocation(root: URL, values: [String]) throws -> ScriptInvocation {
        let parameters = parameters ?? []
        guard values.count == parameters.count, !values.contains(where: { $0.contains("\0") }),
              zip(parameters, values).allSatisfy({ $0.0.required == false || !$0.1.isEmpty }) else {
            throw ExtensionFailure("Fill in all required parameters.")
        }
        let script = root.appending(path: entry)
        var executable = script.path
        var prefix: [String] = []
        if let interpreter, !interpreter.isEmpty {
            if interpreter.hasPrefix("/") { executable = interpreter }
            else {
                guard !interpreter.contains("/"), let found = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
                    .map({ $0 + "/" + interpreter }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                    throw ExtensionFailure("Required interpreter is unavailable: \(interpreter)")
                }
                executable = found
            }
            if executable == "/bin/zsh" { prefix = ["-f"] }
            if executable == "/bin/bash" { prefix = ["--noprofile", "--norc"] }
            prefix.append(script.path)
        }
        guard FileManager.default.isReadableFile(atPath: script.path), FileManager.default.isExecutableFile(atPath: executable) else {
            throw ExtensionFailure("The entry or interpreter is unavailable. Check executable permissions.")
        }
        return ScriptInvocation(executable: executable, arguments: prefix + (arguments ?? []) + values,
                                directory: root.path, timeout: timeout ?? 60)
    }
}

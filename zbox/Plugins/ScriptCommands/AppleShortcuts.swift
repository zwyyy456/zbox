import Foundation

nonisolated struct AppleShortcutConfiguration: Codable, Equatable, Sendable {
    var identifier: UUID
    var name: String
    var acceptsText = false
}

nonisolated struct AppleShortcutEntry: Identifiable, Sendable {
    let id: UUID
    let name: String
}

nonisolated enum AppleShortcutError: LocalizedError {
    case listingFailed, invalidListing, missing, ambiguousName, invalidInput
    var errorDescription: String? {
        switch self {
        case .listingFailed: String(localized: "Could not load Apple Shortcuts. Open Shortcuts and try refreshing the list.")
        case .invalidListing: String(localized: "The shortcut list could not be interpreted. No items were imported.")
        case .missing: String(localized: "This Apple shortcut no longer exists. Select another shortcut in Settings.")
        case .ambiguousName: String(localized: "Several shortcuts have this name. Open the Shortcuts app to edit the intended one.")
        case .invalidInput: String(localized: "Shortcut input must be UTF-8 text no larger than 1 MiB.")
        }
    }
}

nonisolated enum AppleShortcuts {
    @concurrent static func list() async throws -> [AppleShortcutEntry] {
        let result = try await ScriptRunner.run(ScriptInvocation(executable: "/usr/bin/shortcuts",
            arguments: ["list", "--show-identifiers"], directory: NSHomeDirectory(), timeout: 15)) { _ in }
        try Task.checkCancellation()
        guard result.status == 0, !result.timedOut, !result.output.truncated,
              let text = String(data: result.output.stdout, encoding: .utf8) else { throw AppleShortcutError.listingFailed }
        return try parseList(text)
    }

    static func parseList(_ text: String) throws -> [AppleShortcutEntry] {
        try text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            guard line.hasSuffix(")"), let opening = line.lastIndex(of: "("),
                  let id = UUID(uuidString: String(line[line.index(after: opening)..<line.index(before: line.endIndex)])) else {
                throw AppleShortcutError.invalidListing
            }
            let prefix = line[..<opening]
            guard prefix.hasSuffix(" ") else { throw AppleShortcutError.invalidListing }
            let name = String(prefix.dropLast())
            guard !name.isEmpty else { throw AppleShortcutError.invalidListing }
            return AppleShortcutEntry(id: id, name: name)
        }
    }

    static func invocation(_ configuration: AppleShortcutConfiguration, input: String, directory: URL,
                           timeout: Double) throws -> ScriptInvocation {
        var arguments = ["run", configuration.identifier.uuidString, "--output-type", "public.utf8-plain-text"]
        if configuration.acceptsText {
            guard input.utf8.count <= 1_048_576 else { throw AppleShortcutError.invalidInput }
            let file = directory.appending(path: "input.txt")
            try Data(input.utf8).write(to: file)
            arguments += ["--input-path", file.path]
        }
        return ScriptInvocation(executable: "/usr/bin/shortcuts", arguments: arguments, directory: directory.path, timeout: timeout)
    }

    @concurrent static func run(_ configuration: AppleShortcutConfiguration, input: String, timeout: Double,
        onOutput: @escaping @Sendable (ScriptOutput) async -> Void) async throws -> ScriptRunResult {
        let entries = try await list()
        guard entries.contains(where: { $0.id == configuration.identifier }) else { throw AppleShortcutError.missing }
        try Task.checkCancellation()
        let folder = URL.temporaryDirectory.appending(path: "zbox-shortcut-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let command = try invocation(configuration, input: input, directory: folder, timeout: timeout)
            let result = try await ScriptRunner.run(command, onOutput: onOutput)
            try FileManager.default.removeItem(at: folder)
            return result
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    @concurrent static func editorURL(for id: UUID) async throws -> URL {
        let entries = try await list()
        guard let entry = entries.first(where: { $0.id == id }) else { throw AppleShortcutError.missing }
        guard entries.filter({ $0.name == entry.name }).count == 1 else { throw AppleShortcutError.ambiguousName }
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "open-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: entry.name)]
        guard let url = components.url else { throw AppleShortcutError.missing }
        return url
    }
}

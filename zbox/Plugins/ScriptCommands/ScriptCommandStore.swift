import Foundation
import Observation

nonisolated struct ScriptParameter: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var defaultValue = ""
    var required = true
}

nonisolated struct ScriptCommand: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var keywords = ""
    var enabled = true
    var path = ""
    var interpreter = "/bin/zsh"
    var directory = ""
    var arguments: [String] = []
    var parameters: [ScriptParameter] = []
    var shortcut: AppleShortcutConfiguration?
    var timeout = 60.0
    var commandID: CommandID { CommandID("scripts.\(id.uuidString)") }

    func validate() throws {
        if let shortcut {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !shortcut.name.isEmpty, timeout.isFinite, (1...3600).contains(timeout) else {
                throw ScriptCommandError.invalidConfiguration
            }
            return
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              path.hasPrefix("/"), interpreter.isEmpty || interpreter.hasPrefix("/"),
              directory.isEmpty || directory.hasPrefix("/"), timeout.isFinite, (1...3600).contains(timeout),
              parameters.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              !([path, interpreter, directory] + arguments + parameters.map(\.defaultValue)).contains(where: { $0.contains("\0") }) else {
            throw ScriptCommandError.invalidConfiguration
        }
    }

    func invocation(values: [String]) throws -> ScriptInvocation {
        try validate()
        guard shortcut == nil else { throw ScriptCommandError.invalidConfiguration }
        guard values.count == parameters.count,
              zip(parameters, values).allSatisfy({ !$0.0.required || !$0.1.isEmpty }),
              !values.contains(where: { $0.contains("\0") }) else { throw ScriptCommandError.missingParameter }
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
              manager.isReadableFile(atPath: path) else { throw ScriptCommandError.unavailable }
        let executable = interpreter.isEmpty ? path : interpreter
        guard manager.isExecutableFile(atPath: executable) else { throw ScriptCommandError.unavailable }
        let workingDirectory = directory.isEmpty ? URL(filePath: path).deletingLastPathComponent().path : directory
        guard manager.fileExists(atPath: workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScriptCommandError.unavailable
        }
        var prefix: [String] = []
        if !interpreter.isEmpty {
            if interpreter == "/bin/zsh" { prefix = ["-f"] }
            if interpreter == "/bin/bash" { prefix = ["--noprofile", "--norc"] }
            prefix.append(path)
        }
        return ScriptInvocation(executable: executable, arguments: prefix + arguments + values,
                                directory: workingDirectory, timeout: timeout)
    }
}

nonisolated enum ScriptCommandError: LocalizedError {
    case invalidConfiguration, missingParameter, unavailable, unreadableData
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: String(localized: "Enter a name, absolute file paths, named parameters, and a timeout between 1 and 3600 seconds.")
        case .missingParameter: String(localized: "Fill in every required parameter. Null characters are not supported.")
        case .unavailable: String(localized: "The script, interpreter, or working directory is unavailable. Check the paths and executable permissions.")
        case .unreadableData: String(localized: "Script commands could not be read. The saved file has been preserved.")
        }
    }
}

@MainActor @Observable
final class ScriptCommandStore {
    private let url: URL
    private(set) var items: [ScriptCommand] = []
    private(set) var loadError: String?

    init(url: URL = URL.applicationSupportDirectory.appending(path: "zbox/script-commands.json")) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let loaded = try JSONDecoder().decode([ScriptCommand].self, from: Data(contentsOf: url))
            for item in loaded { try item.validate() }
            items = loaded
        } catch { loadError = ScriptCommandError.unreadableData.localizedDescription }
    }

    func save(_ item: ScriptCommand) throws {
        try item.validate()
        var next = items
        if let index = next.firstIndex(where: { $0.id == item.id }) { next[index] = item }
        else { next.append(item) }
        try persist(next)
    }

    func delete(_ id: UUID) throws { try persist(items.filter { $0.id != id }) }

    private func persist(_ items: [ScriptCommand]) throws {
        guard loadError == nil else { throw ScriptCommandError.unreadableData }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: url, options: .atomic)
        self.items = items
    }
}

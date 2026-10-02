import AppKit
import Observation

@MainActor @Observable
final class FileSearchPlugin {
    static let commandID = CommandID("filesearch.open")
    static let shortcutTarget = CommandShortcutTarget(id: commandID, title: String(localized: "File Search"))
    private let defaults: UserDefaults
    let settings = FileSearchSettings()
    private(set) var isEnabled: Bool
    var statusMessage: String?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "filesearch.enabled")
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { stop() }
        isEnabled = enabled
        defaults.set(enabled, forKey: "filesearch.enabled")
    }

    func stop() {}

    func save(_ root: FileSearchRoot) {
        do { try settings.save(root); statusMessage = nil }
        catch { statusMessage = error.localizedDescription }
    }

    func remove(_ root: FileSearchRoot) {
        do { try settings.remove(root.id); statusMessage = nil }
        catch { statusMessage = error.localizedDescription }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { add(url) }
    }

    func add(_ url: URL) {
        do { save(try FileSearchRoot.selected(url)) }
        catch { statusMessage = error.localizedDescription }
    }

    func excludeFolder(from root: FileSearchRoot) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = root.url
        guard panel.runModal() == .OK, let url = panel.url?.resolvingSymlinksInPath().standardizedFileURL else { return }
        guard url != root.url, FileSearchRoot.contains(url, in: root.url) else {
            statusMessage = FileSearchError.outsideRoot.localizedDescription
            return
        }
        var updated = root
        let relative = String(url.path.dropFirst(root.url.path == "/" ? 1 : root.url.path.count + 1))
        if !updated.exclusions.contains(relative) { updated.exclusions.append(relative) }
        save(updated)
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.commandID, title: String(localized: "File Search"),
            subtitle: nil, keywords: ["file", "search", "find", "文件搜索", "查找文件"])) { _ in try openSettings() }
    }
}

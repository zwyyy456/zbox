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
    var rootStatus: [UUID: String] = [:]
    let index = FileIndexStore()
    private let scanner = FileIndexScanner()
    @ObservationIgnored private var scanTasks: [UUID: Task<Void, Never>] = [:]


    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "filesearch.enabled")
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { stop() }
        isEnabled = enabled
        defaults.set(enabled, forKey: "filesearch.enabled")
        if enabled { start() }
    }

    func start() {
        guard isEnabled else { return }
        for root in settings.roots { rescan(root) }
    }

    func stop() {
        for task in scanTasks.values { task.cancel() }
        rootStatus = [:]
    }

    func rescan(_ root: FileSearchRoot) {
        guard isEnabled else { return }
        let previous = scanTasks[root.id]
        previous?.cancel()
        rootStatus[root.id] = String(localized: "Building index…")
        scanTasks[root.id] = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, isEnabled else { return }
            do {
                let count = try await scanner.scan(root, store: index)
                try Task.checkCancellation()
                rootStatus[root.id] = String(localized: "Indexed \(count) items")
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                rootStatus[root.id] = (error as? FileSearchError)?.localizedDescription ?? FileSearchError.scanIncomplete.localizedDescription
            }
        }
    }

    func save(_ root: FileSearchRoot) {
        do { try settings.save(root); statusMessage = nil; rescan(root) }
        catch { statusMessage = error.localizedDescription }
    }

    func remove(_ root: FileSearchRoot) {
        do {
            try settings.remove(root.id)
            let previous = scanTasks[root.id]
            previous?.cancel()
            rootStatus[root.id] = nil
            scanTasks[root.id] = Task { [weak self] in
                await previous?.value
                guard let self, !Task.isCancelled else { return }
                do { try await index.remove(root: root.id) }
                catch { statusMessage = FileSearchError.storage.localizedDescription }
            }
            statusMessage = nil
        }
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

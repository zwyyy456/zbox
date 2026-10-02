import SwiftUI
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
    var query = "" { didSet { search() } }
    var scope = "" { didSet { search() } }
    var typeFilter = "" { didSet { search() } }
    var extensionFilter = "" { didSet { search() } }
    var sort = FileSearchSort.relevance { didSet { search() } }
    private(set) var page = FileSearchPage()
    private(set) var isSearching = false
    var selectedID: String? { didSet { actions.closePreview() } }
    var resultsFocused = false
    private let actions: FileSearchActions
    var searchError: String?
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var panel: FileSearchPanel?
    private var isVisible = false
    var selectedFile: IndexedFile? { page.files.first { $0.id == selectedID } ?? page.files.first }
    let index = FileIndexStore()
    private let scanner = FileIndexScanner()
    @ObservationIgnored private var scanTasks: [UUID: Task<Void, Never>] = [:]


    init(defaults: UserDefaults, coordinator: ClipboardAccessCoordinator) {
        actions = FileSearchActions(coordinator: coordinator)
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
        dismiss()
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
                search()
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

    func search() {
        queryTask?.cancel()
        page = FileSearchPage()
        selectedID = nil
        searchError = nil
        isSearching = false
        guard isEnabled, isVisible else { return }
        let input = query, ext = extensionFilter, type = typeFilter, ordering = sort
        let roots = settings.roots.filter { (scope.isEmpty || $0.id.uuidString == scope) && $0.isAvailable() }
        queryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let parsed = try FileSearchQuery(input, extensionFilter: ext, typeFilter: type)
                guard !parsed.isEmpty else { return }
                isSearching = true
                try await Task.sleep(for: .milliseconds(120))
                let result = try await index.search(parsed, roots: roots, sort: ordering)
                try Task.checkCancellation()
                page = result
                selectedID = result.files.first?.id
                isSearching = false
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                isSearching = false
                searchError = (error as? FileSearchError)?.localizedDescription ?? FileSearchError.storage.localizedDescription
            }
        }
    }

    func dismiss() {
        actions.closePreview()
        isVisible = false
        queryTask?.cancel()
        queryTask = nil
        panel?.orderOut(nil)
        page = FileSearchPage()
        selectedID = nil
        isSearching = false
    }

    func perform(_ action: FileSearchActions.Action) {
        guard let file = selectedFile, let root = settings.roots.first(where: { $0.id == file.rootID }) else { return }
        do {
            guard root.isAvailable() else { throw FileSearchError.missingFile }
            try actions.perform(action, url: root.url.appending(path: file.path))
            searchError = nil
            if action == .open || action == .reveal { dismiss() }
        } catch {
            searchError = (error as? FileSearchError)?.localizedDescription ?? FileSearchError.actionFailed.localizedDescription
            rescan(root)
        }
    }

    func escape() {
        if !actions.closePreview() { dismiss() }
    }

    func moveSelection(_ offset: Int) {
        guard !page.files.isEmpty else { return }
        let current = page.files.firstIndex { $0.id == selectedFile?.id } ?? 0
        selectedID = page.files[min(max(current + offset, 0), page.files.count - 1)].id
    }

    private func show() {
        dismiss()
        query = ""
        scope = ""
        typeFilter = ""
        extensionFilter = ""
        isVisible = true
        if panel == nil {
            let panel = FileSearchPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = String(localized: "File Search")
            panel.navigate = { [weak self] in self?.moveSelection($0) }
            panel.dismiss = { [weak self] in self?.escape() }
            panel.performAction = { [weak self] in self?.perform($0) }
            panel.canPreview = { [weak self] in self?.resultsFocused == true }
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 650, height: 380)
            panel.isReleasedWhenClosed = false
            panel.center()
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: FileSearchView(plugin: self))
        panel?.makeKeyAndOrderFront(nil)
        search()
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.commandID, title: String(localized: "File Search"),
            subtitle: nil, keywords: ["file", "search", "find", "文件搜索", "查找文件"])) { [weak self] _ in
                guard let self else { return }
                guard isEnabled else { try openSettings(); return }
                show()
            }
    }
}

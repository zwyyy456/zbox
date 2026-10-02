import SwiftUI
import Observation
import CoreServices

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
    @ObservationIgnored private var watchers: [UUID: FileIndexWatcher] = [:]
    private var runIDs: [UUID: UUID] = [:]
    private var pending: [UUID: FileIndexChange] = [:]
    @ObservationIgnored private var volumeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    private(set) var isClearing = false
    private var isRunning = false


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
        isRunning = true
        guard !isClearing else { return }
        if volumeObservers.isEmpty {
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didWakeNotification] {
                volumeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refreshVolumes() }
                })
            }
        }
        for root in settings.roots { rescan(root) }
    }

    func stop() {
        isRunning = false
        dismiss()
        for watcher in watchers.values { watcher.stop() }
        watchers = [:]
        for observer in volumeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        volumeObservers = []
        for task in scanTasks.values { task.cancel() }
        runIDs = [:]
        pending = [:]
        rootStatus = [:]
    }

    private func refreshVolumes() {
        guard isEnabled, isRunning, !isClearing else { return }
        for root in settings.roots { rescan(root) }
        search()
    }

    func rescan(_ root: FileSearchRoot) {
        guard isEnabled, isRunning, !isClearing else { return }
        let previous = scanTasks[root.id]
        previous?.cancel()
        watchers.removeValue(forKey: root.id)?.stop()
        pending[root.id] = nil
        let runID = UUID()
        runIDs[root.id] = runID
        rootStatus[root.id] = String(localized: "Building index…")
        scanTasks[root.id] = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, isEnabled else { return }
            defer { if runIDs[root.id] == runID { scanTasks[root.id] = nil } }
            do {
                guard await scanner.availableRoots([root]).count == 1 else { throw FileSearchError.unavailable }
                let baseline = FSEventsGetCurrentEventId()
                let cursor = try await index.cursor(root: root.id)
                try Task.checkCancellation()
                watchers[root.id] = try FileIndexWatcher(root: root, since: min(cursor ?? baseline, baseline)) { [weak self] change in
                    self?.enqueue(change, for: root)
                }
                let count = try await scanner.scan(root, store: index)
                try Task.checkCancellation()
                // The full scan covers changes before baseline; buffered later events are reconciled next.
                try await index.setCursor(baseline, root: root.id)
                try await drainChanges(for: root)
                try Task.checkCancellation()
                rootStatus[root.id] = String(localized: "Index ready (initial scan: \(count) items)")
                search()
            } catch is CancellationError { return }
            catch { reportScanError(error, root: root) }
        }
    }

    private func enqueue(_ change: FileIndexChange, for root: FileSearchRoot) {
        guard isEnabled, isRunning, !isClearing, settings.roots.contains(root) else { return }
        pending[root.id, default: FileIndexChange()].merge(change)
        guard scanTasks[root.id] == nil else { return }
        let runID = UUID()
        runIDs[root.id] = runID
        scanTasks[root.id] = Task { [weak self] in
            guard let self else { return }
            defer { if runIDs[root.id] == runID { scanTasks[root.id] = nil } }
            do {
                try await Task.sleep(for: .milliseconds(200))
                rootStatus[root.id] = String(localized: "Updating index…")
                try await drainChanges(for: root)
                try Task.checkCancellation()
                rootStatus[root.id] = String(localized: "Index ready")
                search()
            } catch is CancellationError { return }
            catch { reportScanError(error, root: root) }
        }
    }

    private func drainChanges(for root: FileSearchRoot) async throws {
        while let change = pending.removeValue(forKey: root.id) {
            try await scanner.reconcile(root, change: change, store: index)
        }
    }

    private func reportScanError(_ error: any Error, root: FileSearchRoot) {
        guard !Task.isCancelled else { return }
        rootStatus[root.id] = (error as? FileSearchError)?.localizedDescription ?? FileSearchError.scanIncomplete.localizedDescription
        // A failed reconciliation is retried as a full scan on the next event or manual rescan.
        pending[root.id, default: FileIndexChange()].directories = [""]
        search()
    }

    func clearIndex() {
        let scans = Array(scanTasks.values)
        let resume = isRunning
        stop()
        isRunning = resume
        isClearing = true
        let previous = cleanupTask
        cleanupTask = Task { [weak self] in
            await previous?.value
            for task in scans { await task.value }
            guard let self else { return }
            defer { isClearing = false; if isRunning { start() } }
            do {
                try await index.clear()
                statusMessage = String(localized: "Index cleared. Enabled search folders will be rebuilt.")
            } catch { statusMessage = FileSearchError.storage.localizedDescription }
        }
    }

    func save(_ root: FileSearchRoot) {
        do { try settings.save(root); statusMessage = nil; rescan(root); search() }
        catch { statusMessage = error.localizedDescription }
    }

    func remove(_ root: FileSearchRoot) {
        do {
            try settings.remove(root.id)
            watchers.removeValue(forKey: root.id)?.stop()
            let scan = scanTasks.removeValue(forKey: root.id)
            scan?.cancel()
            runIDs[root.id] = nil
            pending[root.id] = nil
            rootStatus[root.id] = nil
            let previous = cleanupTask
            cleanupTask = Task { [weak self] in
                await previous?.value
                await scan?.value
                guard let self else { return }
                do { try await index.remove(root: root.id) }
                catch { statusMessage = FileSearchError.storage.localizedDescription }
            }
            statusMessage = nil
            search()
        } catch { statusMessage = error.localizedDescription }
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
        let roots = settings.roots.filter { scope.isEmpty || $0.id.uuidString == scope }
        queryTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                let parsed = try FileSearchQuery(input, extensionFilter: ext, typeFilter: type)
                guard !parsed.isEmpty else { return }
                isSearching = true
                try await Task.sleep(for: .milliseconds(120))
                let available = await scanner.availableRoots(roots)
                try Task.checkCancellation()
                let result = try await index.search(parsed, roots: available, sort: ordering)
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
        query = ""
        searchError = nil
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

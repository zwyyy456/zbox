import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ClipboardHistoryPlugin {
    static let commandID = CommandID("clipboard.history")
    private let defaults: UserDefaults
    private let coordinator: ClipboardAccessCoordinator
    private let authorization: AccessibilityAuthorization
    private var store: ClipboardHistoryStore?
    private var recordingTask: Task<Void, Never>?
    private var recordingID: UUID?
    private var pasteTask: Task<Void, Never>?
    private var targetApplication: NSRunningApplication?
    private(set) var isEnabled: Bool
    private(set) var isRecording = false
    private(set) var needsClipboardAccess = false
    private(set) var statusMessage: String?
    private(set) var entries: [ClipboardEntry] = []
    var showingPastePermission = false
    private(set) var hasMoreEntries = false
    private(set) var storedBytes = 0
    private(set) var storageLimitMiB: Int
    var query = "" { didSet { reloadSearch() } }
    var selectedID: UUID? { didSet { updatePreview() } }
    var filter = ClipboardHistoryFilter.all { didSet { reloadSearch() } }
    private(set) var isPresented = false
    private(set) var previewImage: NSImage?
    private(set) var previewDimensions: String?
    private var previewTask: Task<Void, Never>?
    var retentionDays: Int {
        didSet {
            defaults.set(retentionDays, forKey: "plugin.clipboard-history.retention-days")
            do { try refresh() } catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
        }
    }
    private(set) var excludedApplications: Set<String>
    @ObservationIgnored private var panel: ClipboardHistoryPanel?

    init(defaults: UserDefaults = .standard, coordinator: ClipboardAccessCoordinator,
         authorization: AccessibilityAuthorization) {
        self.defaults = defaults
        self.coordinator = coordinator
        self.authorization = authorization
        isEnabled = defaults.bool(forKey: "plugin.clipboard-history.enabled")
        let days = defaults.integer(forKey: "plugin.clipboard-history.retention-days")
        retentionDays = defaults.object(forKey: "plugin.clipboard-history.retention-days") == nil ? 7 : ([0, 1, 7, 30].contains(days) ? days : 7)
        storageLimitMiB = defaults.integer(forKey: "plugin.clipboard-history.storage-limit-mib")
        excludedApplications = Set(defaults.stringArray(forKey: "plugin.clipboard-history.excluded-apps") ?? [
            "com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password",
            "com.agilebits.onepassword7", "com.bitwarden.desktop",
        ])
    }

    func refreshStorageUsage() {
        do { try prepareStore() }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func setStorageLimitMiB(_ value: Int) {
        do {
            try prepareStore()
            try store?.applyByteLimit(value * 1_024 * 1_024)
            storageLimitMiB = value
            defaults.set(value, forKey: "plugin.clipboard-history.storage-limit-mib")
            try refresh()
            statusMessage = nil
        } catch {
            statusMessage = (error as? ClipboardHistoryError)?.localizedDescription
                ?? String(localized: "Clipboard history could not be opened or saved.")
        }
    }

    private func reloadSearch() {
        do { try refresh(limit: 100) }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func loadMore() {
        do {
            let page = try store?.entries(query: query, filter: filter, offset: entries.count, limit: 101) ?? []
            hasMoreEntries = page.count > 100
            entries.append(contentsOf: page.prefix(100))
        } catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(systemImage: "clipboard", id: Self.commandID, title: String(localized: "Clipboard History"),
            category: String(localized: "Clipboard History"), subtitle: String(localized: "Browse recently copied items"),
            keywords: ["clipboard", "history", "paste", "剪贴板", "剪贴板历史", "粘贴"])) { [weak self] context in
            guard let self else { return }
            guard isEnabled else { try openSettings(); return }
            show(targetPID: context.frontmostApplicationPID)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "plugin.clipboard-history.enabled")
        if enabled { start() } else { stop() }
    }

    func start() {
        guard isEnabled, recordingTask == nil else { return }
        do {
            try prepareStore()
            try ClipboardReader.checkAccess(.general)
        } catch {
            needsClipboardAccess = (error as? ClipboardHistoryError) == .accessRequired
            statusMessage = (error as? ClipboardHistoryError)?.localizedDescription
                ?? String(localized: "Clipboard history could not be opened or saved.")
            return
        }
        needsClipboardAccess = false
        isRecording = true
        statusMessage = nil
        let id = UUID()
        recordingID = id
        recordingTask = Task { [weak self] in
            var lastCount = NSPasteboard.general.changeCount
            var revision = self?.coordinator.revision
            var lastCleanup = Date.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                guard let self, isEnabled else { break }
                if Date.now.timeIntervalSince(lastCleanup) >= 60 {
                    do { try refresh() }
                    catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
                    lastCleanup = .now
                }
                let board = NSPasteboard.general
                if revision != coordinator.revision || coordinator.temporaryAccessCount > 0 {
                    revision = coordinator.revision
                    lastCount = board.changeCount
                    continue
                }
                guard board.changeCount != lastCount else { continue }
                lastCount = board.changeCount
                guard lastCount != coordinator.ignoredChangeCount else { continue }
                let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                do {
                    let payload = try ClipboardReader.read(from: board, excluding: excludedApplications,
                                                           sourceBundleID: source)
                    guard source == NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                          let payload, !Task.isCancelled else { continue }
                    try store?.prune(days: retentionDays)
                    try store?.add(payload, byteLimit: storageLimitMiB * 1_024 * 1_024)
                    try refresh()
                    statusMessage = nil
                } catch ClipboardHistoryError.accessRequired {
                    needsClipboardAccess = true
                    statusMessage = ClipboardHistoryError.accessRequired.localizedDescription
                    break
                } catch ClipboardHistoryError.changed {
                    continue
                } catch {
                    statusMessage = (error as? ClipboardHistoryError)?.localizedDescription
                        ?? String(localized: "Clipboard history could not be opened or saved.")
                }
            }
            if self?.recordingID == id {
                self?.isRecording = false
                self?.recordingTask = nil
            }
        }
    }

    func stop() {
        recordingID = nil
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        needsClipboardAccess = false
        dismiss()
        entries = []
        selectedID = nil
        store = nil
    }

    func requestClipboardAccess() {
        // One explicit access attempt, never a repeating background permission prompt.
        _ = NSPasteboard.general.string(forType: .string)
        start()
    }

    func addExcludedApplication(_ bundleID: String) {
        guard !bundleID.isEmpty else { return }
        excludedApplications.insert(bundleID)
        defaults.set(excludedApplications.sorted(), forKey: "plugin.clipboard-history.excluded-apps")
    }

    func removeExcludedApplication(_ bundleID: String) {
        excludedApplications.remove(bundleID)
        defaults.set(excludedApplications.sorted(), forKey: "plugin.clipboard-history.excluded-apps")
    }

    func chooseExcludedApplication() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.application]
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        addExcludedApplication(id)
    }

    func rowThumbnail(for id: UUID) async -> NSImage? {
        do {
            guard let payload = try store?.payload(for: id) else { return nil }
            let data = try await ClipboardImage.thumbnail(payload.data, maxPixelSize: 64)
            try Task.checkCancellation()
            return NSImage(data: data)
        } catch { return nil }
    }

    private func updatePreview() {
        previewTask?.cancel()
        previewImage = nil
        previewDimensions = nil
        guard let id = selectedID, let entry = entries.first(where: { $0.id == id }),
              ["png", "tiff"].contains(entry.kind) else { return }
        do {
            guard let payload = try store?.payload(for: id) else { return }
            let (width, height) = try ClipboardImage.dimensions(of: payload.data)
            previewDimensions = "\(width) × \(height)"
            previewTask = Task { [weak self] in
                do {
                    let thumbnail = try await ClipboardImage.thumbnail(payload.data)
                    try Task.checkCancellation()
                    guard self?.selectedID == id else { return }
                    self?.previewImage = NSImage(data: thumbnail)
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, self?.selectedID == id else { return }
                    self?.statusMessage = String(localized: "The image preview could not be loaded.")
                }
            }
        } catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func togglePin() {
        guard let entry = entries.first(where: { $0.id == selectedID }) else { return }
        do { try store?.setPinned(!entry.pinned, for: entry.id); try refresh() }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    private func prepareStore() throws {
        if store == nil {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("zento/ClipboardHistory", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store = try ClipboardHistoryStore(url: directory.appendingPathComponent("history.store"))
        }
        try refresh()
    }

    private func refresh(limit: Int? = nil) throws {
        try store?.prune(days: retentionDays)
        let count = limit ?? max(100, entries.count)
        let page = try store?.entries(query: query, filter: filter, limit: count + 1) ?? []
        hasMoreEntries = page.count > count
        entries = Array(page.prefix(count))
        storedBytes = store?.totalBytes ?? 0
        if !entries.contains(where: { $0.id == selectedID }) {
            selectedID = entries.first?.id
        }
    }

    func copySelection() {
        guard let selectedID else { return }
        do {
            guard let payload = try store?.payload(for: selectedID) else { return }
            try write(payload)
            dismiss()
        } catch {
            statusMessage = (error as? ClipboardHistoryError)?.localizedDescription
                ?? String(localized: "Clipboard history could not be opened or saved.")
        }
    }

    func deleteSelection() {
        pasteTask?.cancel()
        guard let selectedID else { return }
        do { try store?.delete(selectedID); try refresh() }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func clearHistory() {
        pasteTask?.cancel()
        do { try prepareStore(); try store?.clear(); try refresh() }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func moveSelection(by offset: Int) {
        guard !entries.isEmpty else { return }
        let index = entries.firstIndex(where: { $0.id == selectedID }) ?? 0
        if index + offset >= entries.count, hasMoreEntries { loadMore() }
        selectedID = entries[min(max(index + offset, 0), entries.count - 1)].id
    }

    private func write(_ payload: ClipboardPayload) throws {
        try ClipboardWriter.write(payload, to: .general, coordinator: coordinator)
    }

    func pasteItem(at index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedID = entries[index].id
        pasteSelection()
    }

    func pasteSelection() {
        guard let selectedID else { return }
        guard authorization.isTrusted else {
            statusMessage = ClipboardPasteError.permissionRequired.localizedDescription
            showingPastePermission = true
            return
        }
        guard let targetApplication else {
            statusMessage = ClipboardPasteError.targetUnavailable.localizedDescription
            return
        }
        do {
            guard let payload = try store?.payload(for: selectedID) else { return }
            pasteTask?.cancel()
            isPresented = false
            panel?.orderOut(nil)
            pasteTask = Task { [weak self] in
                do {
                    try await ClipboardPasteController.activate(targetApplication)
                    try Task.checkCancellation()
                    guard let self, isEnabled else { return }
                    guard authorization.isTrusted else { throw ClipboardPasteError.permissionRequired }
                    try write(payload)
                    try ClipboardPasteController.paste(into: targetApplication)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, self?.isEnabled == true else { return }
                    self?.statusMessage = (error as? ClipboardPasteError)?.localizedDescription
                        ?? (error as? ClipboardHistoryError)?.localizedDescription
                        ?? String(localized: "The item could not be pasted. Copy it and paste manually.")
                    self?.isPresented = true
                    self?.panel?.present()
                }
            }
        } catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    var isPasteTrusted: Bool { authorization.isTrusted }
    func requestPastePermission() { authorization.request() }
    func openAccessibilitySettings() { authorization.openSystemSettings() }

    func dismiss() { dismiss(restoringTarget: true) }

    private func dismiss(restoringTarget: Bool) {
        isPresented = false
        pasteTask?.cancel()
        pasteTask = nil
        previewTask?.cancel()
        previewImage = nil
        previewDimensions = nil
        let target = targetApplication
        targetApplication = nil
        showingPastePermission = false
        panel?.orderOut(nil)
        if restoringTarget, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let target, !target.isTerminated {
            target.activate()
        }
    }

    private func show(targetPID: pid_t?) {
        pasteTask?.cancel()
        targetApplication = targetPID.flatMap(NSRunningApplication.init(processIdentifier:))
        do { try prepareStore() }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
        query = ""
        filter = .all
        selectedID = entries.first?.id
        if panel == nil {
            let panel = ClipboardHistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                                styleMask: [.borderless, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.paste = { [weak self] in self?.pasteSelection() }
            panel.pasteItem = { [weak self] in self?.pasteItem(at: $0) }
            panel.copy = { [weak self] in self?.copySelection() }
            panel.dismiss = { [weak self] in self?.dismiss() }
            panel.dismissAfterFocusLoss = { [weak self] in self?.dismiss(restoringTarget: false) }
            panel.title = String(localized: "Clipboard History")
            let hostingView = NSHostingView(rootView: ClipboardHistoryView(plugin: self))
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = CommandPanelAppearance.cornerRadius
            hostingView.layer?.cornerCurve = .continuous
            hostingView.layer?.masksToBounds = true
            panel.contentView = hostingView
            // The content fills with windowBackgroundColor; keep only the rounded corners transparent.
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.minSize = NSSize(width: 440, height: 320)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.center()
            self.panel = panel
        }
        isPresented = true
        panel?.present()
    }
}

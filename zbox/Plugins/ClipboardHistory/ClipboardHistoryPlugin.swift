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
    private(set) var statusMessage: String?
    private(set) var entries: [ClipboardEntry] = []
    var query = ""
    var selectedID: UUID? { didSet { updatePreview() } }
    var filter = ClipboardHistoryFilter.all
    private(set) var previewImage: NSImage?
    private var previewTask: Task<Void, Never>?
    var retentionDays: Int {
        didSet {
            defaults.set(retentionDays, forKey: "plugin.clipboard-history.retention-days")
            do { try refresh() } catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
        }
    }
    private(set) var excludedApplications: Set<String>
    @ObservationIgnored private var panel: NSPanel?

    init(defaults: UserDefaults = .standard, coordinator: ClipboardAccessCoordinator,
         authorization: AccessibilityAuthorization) {
        self.defaults = defaults
        self.coordinator = coordinator
        self.authorization = authorization
        isEnabled = defaults.bool(forKey: "plugin.clipboard-history.enabled")
        let days = defaults.integer(forKey: "plugin.clipboard-history.retention-days")
        retentionDays = [1, 7, 30].contains(days) ? days : 7
        excludedApplications = Set(defaults.stringArray(forKey: "plugin.clipboard-history.excluded-apps") ?? [
            "com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password",
            "com.agilebits.onepassword7", "com.bitwarden.desktop",
        ])
    }

    var filteredEntries: [ClipboardEntry] {
        entries.filter { entry in
            (query.isEmpty || entry.text.localizedStandardContains(query)) && filter.includes(entry)
        }
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.commandID, title: String(localized: "Clipboard History"),
            subtitle: String(localized: "Browse recently copied items"),
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
            statusMessage = (error as? ClipboardHistoryError)?.localizedDescription
                ?? String(localized: "Clipboard history could not be opened or saved.")
            return
        }
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
                    try store?.add(payload)
                    try refresh()
                    statusMessage = nil
                } catch ClipboardHistoryError.accessRequired {
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

    private func updatePreview() {
        previewTask?.cancel()
        previewImage = nil
        guard let id = selectedID, let entry = entries.first(where: { $0.id == id }),
              ["png", "tiff"].contains(entry.kind) else { return }
        do {
            guard let payload = try store?.payload(for: id) else { return }
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
                .appendingPathComponent("zbox/ClipboardHistory", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store = try ClipboardHistoryStore(url: directory.appendingPathComponent("history.store"))
        }
        try refresh()
    }

    private func refresh() throws {
        try store?.prune(days: retentionDays)
        entries = try store?.entries() ?? []
        if !filteredEntries.contains(where: { $0.id == selectedID }) {
            selectedID = filteredEntries.first?.id
        }
    }

    func copySelection() {
        guard let selectedID else { return }
        do {
            guard let payload = try store?.payload(for: selectedID) else { return }
            try write(payload)
            panel?.orderOut(nil)
        } catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
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
        let entries = filteredEntries
        guard !entries.isEmpty else { return }
        let index = entries.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = entries[min(max(index + offset, 0), entries.count - 1)].id
    }

    private func write(_ payload: ClipboardPayload) throws {
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        defer { coordinator.didWrite(changeCount: board.changeCount) }
        let copied: Bool
        if ["png", "tiff"].contains(payload.kind) {
            copied = board.setData(payload.data, forType: payload.kind == "png" ? .png : .tiff)
        } else {
            copied = board.setString(payload.text, forType: .string)
        }
        guard copied else {
            throw ClipboardHistoryError.unsupported
        }
    }

    func pasteSelection() {
        guard let selectedID else { return }
        guard authorization.isTrusted else {
            statusMessage = ClipboardHistoryError.pastePermissionRequired.localizedDescription
            return
        }
        guard let targetApplication else {
            statusMessage = ClipboardHistoryError.targetUnavailable.localizedDescription
            return
        }
        do {
            guard let payload = try store?.payload(for: selectedID) else { return }
            pasteTask?.cancel()
            panel?.orderOut(nil)
            pasteTask = Task { [weak self] in
                do {
                    try await ClipboardPasteController.activate(targetApplication)
                    try Task.checkCancellation()
                    guard let self, isEnabled else { return }
                    guard authorization.isTrusted else { throw ClipboardHistoryError.pastePermissionRequired }
                    try write(payload)
                    try ClipboardPasteController.paste(into: targetApplication)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, self?.isEnabled == true else { return }
                    self?.statusMessage = (error as? ClipboardHistoryError)?.localizedDescription
                        ?? String(localized: "The item could not be pasted. Copy it and paste manually.")
                    self?.panel?.makeKeyAndOrderFront(nil)
                }
            }
        } catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func requestPastePermission() { authorization.request() }
    func openAccessibilitySettings() { authorization.openSystemSettings() }

    func dismiss() {
        pasteTask?.cancel()
        pasteTask = nil
        previewTask?.cancel()
        previewImage = nil
        targetApplication = nil
        panel?.orderOut(nil)
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
                                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.navigate = { [weak self] in self?.moveSelection(by: $0) }
            panel.paste = { [weak self] in self?.pasteSelection() }
            panel.copy = { [weak self] in self?.copySelection() }
            panel.dismiss = { [weak self] in self?.dismiss() }
            panel.title = String(localized: "Clipboard History")
            panel.contentView = NSHostingView(rootView: ClipboardHistoryView(plugin: self))
            panel.minSize = NSSize(width: 440, height: 320)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

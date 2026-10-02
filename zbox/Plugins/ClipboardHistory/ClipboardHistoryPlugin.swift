import AppKit
import Observation
import SwiftUI

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
    private(set) var isEnabled: Bool
    private(set) var isRecording = false
    private(set) var statusMessage: String?
    private(set) var entries: [ClipboardEntry] = []
    var query = ""
    var selectedID: UUID?
    @ObservationIgnored private var panel: NSPanel?

    init(defaults: UserDefaults = .standard, coordinator: ClipboardAccessCoordinator,
         authorization: AccessibilityAuthorization) {
        self.defaults = defaults
        self.coordinator = coordinator
        self.authorization = authorization
        isEnabled = defaults.bool(forKey: "plugin.clipboard-history.enabled")
    }

    var filteredEntries: [ClipboardEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedStandardContains(query) }
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.commandID, title: String(localized: "Clipboard History"),
            subtitle: String(localized: "Browse recently copied items"),
            keywords: ["clipboard", "history", "paste", "剪贴板", "剪贴板历史", "粘贴"])) { [weak self] _ in
            guard let self else { return }
            guard isEnabled else { try openSettings(); return }
            show()
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
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                guard let self, isEnabled else { break }
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
        panel?.orderOut(nil)
        entries = []
        selectedID = nil
        store = nil
    }

    func requestClipboardAccess() {
        // One explicit access attempt, never a repeating background permission prompt.
        _ = NSPasteboard.general.string(forType: .string)
        start()
    }

    private var excludedApplications: Set<String> {
        ["com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password",
         "com.agilebits.onepassword7", "com.bitwarden.desktop"]
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
        entries = try store?.entries() ?? []
        if !filteredEntries.contains(where: { $0.id == selectedID }) {
            selectedID = filteredEntries.first?.id
        }
    }

    func copySelection() {
        guard let selectedID else { return }
        do {
            guard let payload = try store?.payload(for: selectedID) else { return }
            let board = NSPasteboard.general
            board.prepareForNewContents(with: .currentHostOnly)
            guard board.setString(payload.text, forType: .string) else {
                statusMessage = String(localized: "The item could not be copied.")
                return
            }
            coordinator.didWrite(changeCount: board.changeCount)
            panel?.orderOut(nil)
        } catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func deleteSelection() {
        guard let selectedID else { return }
        do { try store?.delete(selectedID); try refresh() }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func clearHistory() {
        do { try prepareStore(); try store?.clear(); try refresh() }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
    }

    func dismiss() { panel?.orderOut(nil) }

    private func show() {
        do { try prepareStore() }
        catch { statusMessage = String(localized: "Clipboard history could not be opened or saved.") }
        query = ""
        selectedID = entries.first?.id
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
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

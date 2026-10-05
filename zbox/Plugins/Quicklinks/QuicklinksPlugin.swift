import SwiftUI
import Observation

@MainActor @Observable
final class QuicklinksPlugin {
    static let selectionCommandID = CommandID("quicklinks.selection")
    static let commandID = CommandID("quicklinks.manage")
    private let defaults: UserDefaults
    let store = QuicklinkStore()
    private(set) var isEnabled: Bool
    var statusMessage: String?
    var choosingTemplate = false
    var parameterItem: Quicklink?
    var query = ""
    var parameterError: String?
    @ObservationIgnored private var panel: QuicklinkParameterPanel?


    var shortcutTargets: [CommandShortcutTarget] {
        [CommandShortcutTarget(id: Self.selectionCommandID, title: String(localized: "Quicklink with Selected Text"))]
            + store.items.map { CommandShortcutTarget(id: $0.commandID, title: $0.name) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "quicklinks.enabled")
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { stop() }
        isEnabled = enabled
        defaults.set(enabled, forKey: "quicklinks.enabled")
    }

    func stop() {
        panel?.orderOut(nil)
        choosingTemplate = false
        parameterItem = nil
        query = ""
        parameterError = nil
    }

    func openParameterizedLink() {
        guard isEnabled, let parameterItem else { return }
        do {
            let url = try QuicklinkTemplate(parameterItem.target).destination(query: query)
            guard NSWorkspace.shared.open(url) else { throw QuicklinkError.openFailed }
            stop()
        } catch { parameterError = error.localizedDescription }
    }

    private func showParameters(for item: Quicklink, selectedText: String? = nil) {
        choosingTemplate = selectedText != nil
        parameterItem = item
        query = selectedText ?? ""
        parameterError = nil
        if panel == nil {
            let panel = QuicklinkParameterPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
                styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = String(localized: "Quicklinks")
            panel.onDismiss = { [weak self] in self?.stop() }
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.center()
            self.panel = panel
        }
        panel?.setContentSize(NSSize(width: 520, height: choosingTemplate ? 290 : 220))
        panel?.contentView = NSHostingView(rootView: QuicklinkParameterView(plugin: self))
        panel?.makeKeyAndOrderFront(nil)
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.commandID, title: String(localized: "Quicklinks"),
            subtitle: nil, keywords: ["quicklinks", "links", "快捷入口", "链接"])) { _ in try openSettings() }
        try registry.register(CommandDescriptor(id: Self.selectionCommandID, title: String(localized: "Quicklink with Selected Text"),
            subtitle: String(localized: "Quicklinks"), keywords: ["selection", "selected", "选中", "搜索", "链接"])) { [weak self] context in
                guard let self else { return }
                guard isEnabled else { try openSettings(); return }
                guard let item = store.items.first(where: { $0.kind == .template }) else { throw QuicklinkSelectionError.noTemplate }
                let text = try await SelectedTextReader.read(targetPID: context.frontmostApplicationPID)
                guard isEnabled else { return }
                showParameters(for: item, selectedText: text)
            }
        guard isEnabled else { return }
        for item in store.items {
            try registry.register(CommandDescriptor(id: item.commandID, title: item.name,
                subtitle: String(localized: "Quicklinks"), keywords: item.keywords.components(separatedBy: .whitespacesAndNewlines))) { [weak self] _ in
                guard let self, isEnabled else { return }
                if item.kind == .template { showParameters(for: item); return }
                let url = try item.destination()
                if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) { throw QuicklinkError.missingFile }
                guard NSWorkspace.shared.open(url) else { throw QuicklinkError.openFailed }
            }
        }
    }
}

nonisolated enum QuicklinkSelectionError: LocalizedError {
    case noTemplate
    var errorDescription: String? { String(localized: "Add a parameterized Quicklink in Settings first.") }
}

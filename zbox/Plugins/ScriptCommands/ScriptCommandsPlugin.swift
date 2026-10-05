import SwiftUI

@MainActor @Observable
final class ScriptCommandsPlugin {
    static let manageID = CommandID("scripts.manage")
    let store: ScriptCommandStore
    private let defaults: UserDefaults
    private(set) var isEnabled: Bool
    var statusMessage: String?
    var selected: ScriptCommand?
    var values: [String] = []
    @ObservationIgnored private var window: NSWindow?

    var shortcutTargets: [CommandShortcutTarget] {
        store.items.map { CommandShortcutTarget(id: $0.commandID, title: $0.name) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        store = ScriptCommandStore()
        isEnabled = defaults.bool(forKey: "scripts.enabled")
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { stop() }
        isEnabled = enabled
        defaults.set(enabled, forKey: "scripts.enabled")
    }

    func stop() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        selected = nil
        values = []
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.manageID, title: String(localized: "Script Commands"),
            subtitle: nil, keywords: ["script", "shell", "脚本", "命令"])) { _ in try openSettings() }
        guard isEnabled else { return }
        for item in store.items where item.enabled {
            try registry.register(CommandDescriptor(id: item.commandID, title: item.name,
                subtitle: String(localized: "Script Commands"), keywords: item.keywords.components(separatedBy: .whitespacesAndNewlines))) { [weak self] _ in
                self?.show(item)
            }
        }
    }

    private func show(_ item: ScriptCommand) {
        selected = item
        values = item.parameters.map(\.defaultValue)
        statusMessage = nil
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = String(localized: "Script Commands")
            window.minSize = CGSize(width: 600, height: 400)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ScriptCommandView(plugin: self))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ScriptCommandView: View {
    @Bindable var plugin: ScriptCommandsPlugin
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = plugin.selected {
                Text(item.name).font(.title2)
                Text(item.path).font(.caption).textSelection(.enabled)
                ForEach(Array(item.parameters.enumerated()), id: \.element.id) { index, parameter in
                    TextField(parameter.name, text: $plugin.values[index]).textFieldStyle(.roundedBorder)
                }
                Button("Reveal Script in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: item.path)]) }
            }
            if let message = plugin.statusMessage { Text(message).foregroundStyle(.red) }
            Spacer()
        }.padding(20)
    }
}

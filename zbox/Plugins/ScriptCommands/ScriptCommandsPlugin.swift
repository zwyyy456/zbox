import SwiftUI

@MainActor @Observable
final class ScriptCommandsPlugin {
    static let manageID = CommandID("scripts.manage")
    let store: ScriptCommandStore
    private let coordinator: ClipboardAccessCoordinator
    private let defaults: UserDefaults
    private(set) var isEnabled: Bool
    var statusMessage: String?
    var selected: ScriptCommand?
    var values: [String] = []
    var shortcutInput = ""
    private(set) var isRunning = false
    private(set) var output = ScriptOutput()
    private(set) var result: ScriptRunResult?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var editorTask: Task<Void, Never>?
    @ObservationIgnored private var window: NSWindow?

    var shortcutTargets: [CommandShortcutTarget] {
        store.items.map { CommandShortcutTarget(id: $0.commandID, title: $0.name) }
    }

    init(defaults: UserDefaults, coordinator: ClipboardAccessCoordinator) {
        self.coordinator = coordinator
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
        editorTask?.cancel(); editorTask = nil
        task?.cancel()
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        if !isRunning {
            selected = nil
            values = []
            shortcutInput = ""
            clear()
        }
    }

    func waitForStop() async { await task?.value }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.manageID, title: String(localized: "Automation"),
            subtitle: nil, keywords: ["script", "shell", "shortcuts", "automation", "脚本", "命令", "快捷指令", "自动化"])) { _ in try openSettings() }
        guard isEnabled else { return }
        for item in store.items where item.enabled {
            try registry.register(CommandDescriptor(id: item.commandID, title: item.name,
                subtitle: String(localized: "Automation"), keywords: item.keywords.components(separatedBy: .whitespacesAndNewlines))) { [weak self] _ in
                self?.show(item)
            }
        }
    }

    private func show(_ item: ScriptCommand) {
        if !isRunning {
            selected = item
            values = item.parameters.map(\.defaultValue)
            shortcutInput = ""
            clear()
        }
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = String(localized: "Automation")
            window.minSize = CGSize(width: 600, height: 400)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ScriptCommandView(plugin: self))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        if !isRunning, item.shortcut.map({ !$0.acceptsText }) ?? item.parameters.isEmpty { run() }
    }

    func run() {
        guard isEnabled, !isRunning, let selected else { return }
        do {
            try selected.validate()
            let invocation = try selected.shortcut == nil ? selected.invocation(values: values) : nil
            let input = shortcutInput
            if selected.shortcut?.acceptsText == true, input.utf8.count > 1_048_576 { throw AppleShortcutError.invalidInput }
            clear()
            isRunning = true
            task = Task { [weak self] in
                do {
                    let result: ScriptRunResult
                    if let shortcut = selected.shortcut {
                        result = try await AppleShortcuts.run(shortcut, input: input, timeout: selected.timeout) { [weak self] output in
                            await self?.update(output)
                        }
                    } else if let invocation {
                        result = try await ScriptRunner.run(invocation) { [weak self] output in await self?.update(output) }
                    } else { throw ScriptCommandError.invalidConfiguration }
                    self?.result = result
                    if selected.shortcut != nil, result.cancelled || result.timedOut {
                        self?.statusMessage = String(localized: "Stopped waiting. The shortcut may still be running in Shortcuts.")
                    }
                } catch is CancellationError {
                    self?.statusMessage = selected.shortcut == nil ? String(localized: "Cancelled")
                        : String(localized: "Stopped waiting. The shortcut may still be running in Shortcuts.")
                } catch { self?.statusMessage = error.localizedDescription }
                self?.isRunning = false
                self?.task = nil
                if self?.window == nil { self?.stop() }
            }
        } catch { statusMessage = error.localizedDescription }
    }

    func openShortcut() {
        guard let id = selected?.shortcut?.identifier else { return }
        editorTask?.cancel()
        editorTask = Task { [weak self] in
            do {
                let url = try await AppleShortcuts.editorURL(for: id)
                try Task.checkCancellation()
                guard NSWorkspace.shared.open(url) else { throw AppleShortcutError.missing }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self?.statusMessage = error.localizedDescription } }
        }
    }

    private func update(_ output: ScriptOutput) { self.output = output }
    func cancel() { task?.cancel() }
    func clear() {
        guard !isRunning else { return }
        output = ScriptOutput()
        result = nil
        statusMessage = nil
    }
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let success = pasteboard.setString(text, forType: .string)
        coordinator.didWrite(changeCount: pasteboard.changeCount)
        if !success { statusMessage = String(localized: "Could not copy the result.") }
    }
}

struct ScriptCommandView: View {
    @Bindable var plugin: ScriptCommandsPlugin
    @State private var showsError = false
    private var text: String { String(decoding: showsError ? plugin.output.stderr : plugin.output.stdout, as: UTF8.self) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = plugin.selected {
                Text(item.name).font(.title2)
                Text(item.shortcut?.name ?? item.path).font(.caption).textSelection(.enabled)
                if let shortcut = item.shortcut {
                    if shortcut.acceptsText {
                        PlainTextEditor(text: $plugin.shortcutInput, label: String(localized: "Shortcut Input"))
                            .frame(height: 90).disabled(plugin.isRunning)
                    }
                    Text("Stopping or timing out only stops waiting in zbox. The shortcut may continue in Shortcuts.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                ForEach(Array(item.parameters.enumerated()), id: \.element.id) { index, parameter in
                    TextField(parameter.name, text: $plugin.values[index]).textFieldStyle(.roundedBorder)
                        .disabled(plugin.isRunning)
                }
                }
                HStack {
                    Button("Run", action: plugin.run).keyboardShortcut(.return, modifiers: .command).disabled(plugin.isRunning)
                    Button(item.shortcut == nil ? String(localized: "Stop") : String(localized: "Stop Waiting"), action: plugin.cancel).disabled(!plugin.isRunning)
                    if item.shortcut != nil {
                        Button("Open in Shortcuts", action: plugin.openShortcut)
                    } else {
                        Button("Reveal Script in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: item.path)]) }
                    }
                    Spacer()
                    if plugin.isRunning { ProgressView().controlSize(.small); Text("Running…") }
                    else if let result = plugin.result {
                        if result.cancelled { Text(item.shortcut == nil ? String(localized: "Cancelled") : String(localized: "Stopped Waiting")) }
                        else if result.timedOut { Text("Timed Out") }
                        else if result.status & 0x7f != 0 { Text("Signal: \(result.status & 0x7f)") }
                        else { Text("Exit Code: \((result.status >> 8) & 0xff)") }
                    }
                }
            }
            Picker("Output", selection: $showsError) {
                Text("Standard Output").tag(false)
                Text("Standard Error").tag(true)
            }.pickerStyle(.segmented)
            PlainTextEditor(text: .constant(text), isEditable: false, label: String(localized: "Output"))
            HStack {
                Button("Copy Output") { plugin.copy(text) }.disabled(text.isEmpty)
                Button("Clear", action: plugin.clear).disabled(plugin.isRunning)
                if plugin.output.truncated { Text("Output limited to 1 MiB per stream.").font(.caption).foregroundStyle(.secondary) }
            }
            if let message = plugin.statusMessage { Text(message).foregroundStyle(.red) }
        }.padding(20)
    }
}

import SwiftUI

@MainActor @Observable
final class SnippetsPlugin {
    static let commandID = CommandID("snippets.open")
    private let defaults: UserDefaults
    private let coordinator: ClipboardAccessCoordinator
    let store = SnippetStore()
    private(set) var isEnabled: Bool
    var statusMessage: String?
    var query = ""
    var group = ""
    var selectedID: UUID?
    @ObservationIgnored private var panel: SnippetsPanel?

    var groups: [String] { Set(store.items.map(\.group).filter { !$0.isEmpty }).sorted() }
    var filteredItems: [Snippet] {
        store.items.filter {
            (group.isEmpty || $0.group == group) && (query.isEmpty ||
                [$0.name, $0.keywords, $0.body].contains { $0.localizedStandardContains(query) })
        }
    }
    var selectedItem: Snippet? { filteredItems.first { $0.id == selectedID } ?? filteredItems.first }
    var shortcutTargets: [CommandShortcutTarget] {
        [CommandShortcutTarget(id: Self.commandID, title: String(localized: "Snippets"))]
    }

    init(defaults: UserDefaults, coordinator: ClipboardAccessCoordinator) {
        self.defaults = defaults
        self.coordinator = coordinator
        isEnabled = defaults.bool(forKey: "snippets.enabled")
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled { stop() }
        isEnabled = enabled
        defaults.set(enabled, forKey: "snippets.enabled")
    }

    func stop() {
        panel?.orderOut(nil)
        query = ""
        group = ""
        selectedID = nil
        statusMessage = nil
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.commandID, title: String(localized: "Snippets"),
            subtitle: nil, keywords: ["snippets", "text", "文本片段", "模板"])) { [weak self] _ in
            guard let self else { return }
            guard isEnabled else { try openSettings(); return }
            show()
        }
    }

    func moveSelection(by offset: Int) {
        let items = filteredItems
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedItem?.id } ?? 0
        selectedID = items[min(max(index + offset, 0), items.count - 1)].id
    }

    func copySelection() {
        guard isEnabled, let item = selectedItem else { return }
        do { try write(item.body); stop() }
        catch { statusMessage = error.localizedDescription }
    }

    private func write(_ text: String) throws {
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        defer { coordinator.didWrite(changeCount: board.changeCount) }
        guard board.setString(text, forType: .string) else { throw SnippetError.copyFailed }
    }

    private func show() {
        stop()
        if panel == nil {
            let panel = SnippetsPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = String(localized: "Snippets")
            panel.navigate = { [weak self] in self?.moveSelection(by: $0) }
            panel.execute = { [weak self] in self?.copySelection() }
            panel.copy = { [weak self] in self?.copySelection() }
            panel.dismiss = { [weak self] in self?.stop() }
            panel.contentView = NSHostingView(rootView: SnippetsView(plugin: self))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 580, height: 360)
            panel.isReleasedWhenClosed = false
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}

@MainActor final class SnippetsPanel: NSPanel {
    var navigate: ((Int) -> Void)?
    var execute: (() -> Void)?
    var copy: (() -> Void)?
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func close() { dismiss?(); super.close() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true {
            let modifiers = event.modifierFlags.intersection([.command, .control, .shift, .option])
            if [36, 76].contains(event.keyCode), modifiers == .command { copy?(); return }
            if let action = SearchKeyboardMapper.action(keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifierFlags: event.modifierFlags) {
                switch action {
                case .moveSelection(let offset): navigate?(offset)
                case .execute: execute?()
                case .dismiss: dismiss?()
                }
                return
            }
        }
        super.sendEvent(event)
    }
}

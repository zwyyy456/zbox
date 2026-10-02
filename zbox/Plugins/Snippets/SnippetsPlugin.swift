import SwiftUI

@MainActor @Observable
final class SnippetsPlugin {
    static let commandID = CommandID("snippets.open")
    private let defaults: UserDefaults
    private let coordinator: ClipboardAccessCoordinator
    private let authorization = AccessibilityAuthorization()
    @ObservationIgnored private var pasteTask: Task<Void, Never>?
    @ObservationIgnored private var targetApplication: NSRunningApplication?
    let store = SnippetStore()
    private(set) var isEnabled: Bool
    var statusMessage: String?
    private(set) var needsPastePermission = false
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
            + store.items.map { CommandShortcutTarget(id: $0.commandID, title: $0.name) }
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
        pasteTask?.cancel()
        pasteTask = nil
        targetApplication = nil
        panel?.orderOut(nil)
        query = ""
        group = ""
        selectedID = nil
        statusMessage = nil
        needsPastePermission = false
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(id: Self.commandID, title: String(localized: "Snippets"),
            subtitle: nil, keywords: ["snippets", "text", "文本片段", "模板"])) { [weak self] context in
            guard let self else { return }
            guard isEnabled else { try openSettings(); return }
            show(targetPID: context.frontmostApplicationPID)
        }
        guard isEnabled else { return }
        for item in store.items {
            try registry.register(CommandDescriptor(id: item.commandID, title: item.name,
                subtitle: String(localized: "Snippets"), keywords: item.keywords.components(separatedBy: .whitespacesAndNewlines))) { [weak self] context in
                guard let self, isEnabled else { return }
                show(targetPID: context.frontmostApplicationPID)
                selectedID = item.id
                pasteSelection()
            }
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
        pasteTask?.cancel()
        do { try write(item.body); stop() }
        catch { statusMessage = error.localizedDescription }
    }

    func pasteSelection() {
        guard isEnabled, let item = selectedItem else { return }
        guard authorization.isTrusted else {
            needsPastePermission = true
            statusMessage = ClipboardPasteError.permissionRequired.localizedDescription
            return
        }
        guard let targetApplication else {
            statusMessage = ClipboardPasteError.targetUnavailable.localizedDescription
            return
        }
        needsPastePermission = false
        pasteTask?.cancel()
        panel?.orderOut(nil)
        pasteTask = Task { [weak self] in
            do {
                try await ClipboardPasteController.activate(targetApplication)
                try Task.checkCancellation()
                guard let self, isEnabled else { return }
                guard authorization.isTrusted else { throw ClipboardPasteError.permissionRequired }
                try write(item.body)
                try ClipboardPasteController.paste(into: targetApplication)
                stop()
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, isEnabled else { return }
                if case ClipboardPasteError.permissionRequired = error { needsPastePermission = true }
                statusMessage = error.localizedDescription
                panel?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func requestPastePermission() { authorization.request() }
    func openAccessibilitySettings() { authorization.openSystemSettings() }

    private func write(_ text: String) throws {
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        defer { coordinator.didWrite(changeCount: board.changeCount) }
        guard board.setString(text, forType: .string) else { throw SnippetError.copyFailed }
    }

    private func show(targetPID: pid_t?) {
        stop()
        targetApplication = targetPID.flatMap(NSRunningApplication.init(processIdentifier:))
        selectedID = filteredItems.first?.id
        if panel == nil {
            let panel = SnippetsPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = String(localized: "Snippets")
            panel.navigate = { [weak self] in self?.moveSelection(by: $0) }
            panel.execute = { [weak self] in self?.pasteSelection() }
            panel.copy = { [weak self] in self?.copySelection() }
            panel.dismiss = { [weak self] in self?.stop() }
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 580, height: 360)
            panel.isReleasedWhenClosed = false
            panel.center()
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: SnippetsView(plugin: self))
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

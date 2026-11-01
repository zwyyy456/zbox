import SwiftUI

@MainActor @Observable
final class AppMenuPlugin {
    static let commandID = CommandID("app-menu.search")
    static var shortcutTarget: CommandShortcutTarget {
        CommandShortcutTarget(id: commandID, title: String(localized: "Search Application Menu"))
    }
    private let defaults: UserDefaults
    private let controller = AppMenuController()
    private let authorization = AccessibilityAuthorization()
    private(set) var isEnabled: Bool
    var statusMessage: String?
    var query = ""
    var applicationName = ""
    var items: [AppMenuItem] = []
    var selectedID: UUID?
    var isLoading = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var panel: AppMenuPanel?
    var filteredItems: [AppMenuItem] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return items.filter { item in words.allSatisfy { (item.title + " " + item.path).localizedStandardContains($0) } }
    }
    var selected: AppMenuItem? { filteredItems.first { $0.id == selectedID } ?? filteredItems.first }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "app-menu.enabled")
    }
    func setEnabled(_ enabled: Bool) {
        if enabled, !authorization.isTrusted { statusMessage = AppMenuError.permissionRequired.localizedDescription; return }
        isEnabled = enabled
        defaults.set(enabled, forKey: "app-menu.enabled")
        if !enabled { stop() }
        statusMessage = nil
    }
    func stop() {
        task?.cancel(); task = nil
        panel?.orderOut(nil)
        controller.clear()
        items = []; query = ""; selectedID = nil; applicationName = ""; isLoading = false
    }
    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        try registry.register(CommandDescriptor(systemImage: "menubar.rectangle", id: Self.commandID, title: Self.shortcutTarget.title, category: String(localized: "Application Menu"), subtitle: nil,
            keywords: ["menu", "application", "菜单", "应用菜单"])) { [weak self] context in
                guard let self else { return }
                guard isEnabled else { try openSettings(); return }
                guard authorization.isTrusted else { setEnabled(false); try openSettings(); return }
                show(pid: context.frontmostApplicationPID)
            }
    }
    func navigate(_ offset: Int) {
        let results = filteredItems
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = results[min(max(index + offset, 0), results.count - 1)].id
    }
    func executeSelection() {
        guard isEnabled, !isLoading, let selected, selected.enabled else { return }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do { try await controller.execute(selected.id); stop() }
            catch is CancellationError { }
            catch { if !Task.isCancelled { statusMessage = error.localizedDescription } }
        }
    }
    private func show(pid: pid_t?) {
        stop()
        statusMessage = nil
        isLoading = true
        if panel == nil {
            let panel = AppMenuPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = String(localized: "Application Menu")
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 480, height: 320)
            panel.dismiss = { [weak self] in self?.stop() }
            panel.navigate = { [weak self] in self?.navigate($0) }
            panel.execute = { [weak self] in self?.executeSelection() }
            panel.center()
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: AppMenuView(plugin: self))
        panel?.makeKeyAndOrderFront(nil)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let (name, items) = try await controller.load(pid: pid)
                try Task.checkCancellation()
                applicationName = name; self.items = items
                isLoading = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { isLoading = false; statusMessage = error.localizedDescription } }
        }
    }
}

private final class AppMenuPanel: NSPanel {
    var dismiss: (() -> Void)?
    var navigate: ((Int) -> Void)?
    var execute: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func close() { dismiss?(); super.close() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true,
           let action = SearchKeyboardMapper.action(keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifierFlags: event.modifierFlags) {
            switch action {
            case .moveSelection(let offset): navigate?(offset)
            case .execute: execute?()
            case .dismiss: dismiss?()
            }
            return
        }
        super.sendEvent(event)
    }
}

private struct AppMenuView: View {
    @Bindable var plugin: AppMenuPlugin
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            ToolSearchBar {
                TextField("Search Menu Items", text: $plugin.query).focused($searchFocused)
            } accessory: {
                if plugin.isLoading {
                    ProgressView()
                } else if !plugin.applicationName.isEmpty {
                    Text(plugin.applicationName).foregroundStyle(.secondary)
                }
            }
            List(selection: Binding(get: { plugin.selected?.id }, set: { plugin.selectedID = $0 })) {
                ForEach(plugin.filteredItems) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if item.marked { Image(systemName: "checkmark").accessibilityLabel(Text("Checked")) }
                        if !item.shortcut.isEmpty {
                            Text(item.shortcut).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if !item.enabled { Text("Unavailable").font(.caption) }
                    }.foregroundStyle(item.enabled ? .primary : .secondary).tag(item.id)
                }
            }
            .overlay {
                if !plugin.isLoading, plugin.filteredItems.isEmpty {
                    ContentUnavailableView("No Menu Items Found", systemImage: "menubar.rectangle",
                                           description: Text("Try a different menu item name."))
                }
            }
            ToolActionBar(primaryTitle: String(localized: "Execute Menu Item"),
                          isPrimaryEnabled: plugin.selected?.enabled == true && !plugin.isLoading,
                          primary: plugin.executeSelection) {
                if let message = plugin.statusMessage {
                    SettingsErrorView(message: message)
                } else {
                    Text("Esc Close")
                }
            }
        }.onAppear { searchFocused = true }.onChange(of: plugin.query) { plugin.selectedID = nil }
    }
}

struct AppMenuSettingsView: View {
    let environment: AppEnvironment
    var body: some View {
        Form {
            Toggle("Enable Application Menu Search", isOn: Binding(get: { environment.appMenuPlugin.isEnabled }, set: environment.setAppMenuEnabled))
            Text("Search and execute the original application's accessible menu items. Menu contents are not saved.").foregroundStyle(.secondary)
            AccessibilityPermissionRow(isTrusted: environment.isAccessibilityTrusted,
                                       request: environment.requestAccessibilityPermission,
                                       openSettings: environment.openAccessibilitySettings)
            if let message = environment.appMenuPlugin.statusMessage { SettingsErrorView(message: message) }
            if let message = environment.shortcutRegistrationError { SettingsErrorView(message: message) }
        }.settingsPane()
    }
}

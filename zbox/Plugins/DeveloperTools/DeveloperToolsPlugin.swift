import SwiftUI

@MainActor
@Observable
final class DeveloperToolsPlugin: NSObject, NSWindowDelegate {
    enum Tool: String, CaseIterable, Identifiable {
        case json, uuid, url, base64

        var id: String { rawValue }
        var title: String {
            switch self {
            case .json: String(localized: "JSON Format / Validate")
            case .uuid: String(localized: "UUID Generator")
            case .url: String(localized: "URL Encode / Decode")
            case .base64: String(localized: "Base64 Encode / Decode")
            }
        }
        var icon: String {
            switch self {
            case .json: "curlybraces"
            case .uuid: "number"
            case .url: "link"
            case .base64: "textformat.abc"
            }
        }
        var commandID: CommandID { CommandID("developer-tools.\(rawValue)") }
    }

    static let commandID = CommandID("developer-tools.open")
    static var shortcutTargets: [CommandShortcutTarget] {
        [CommandShortcutTarget(id: commandID, title: String(localized: "Developer Tools"))]
            + Tool.allCases.map { CommandShortcutTarget(id: $0.commandID, title: $0.title) }
    }

    var selection: Tool = .json
    var jsonSession = DeveloperTextSession(kind: .json)
    var urlSession = DeveloperTextSession(kind: .url)
    var base64Session = DeveloperTextSession(kind: .base64)
    var uuidCount = 1
    var uppercaseUUIDs = false
    private(set) var uuids: [UUID] = []
    var copyError: String?

    @ObservationIgnored private var window: NSWindow?
    private let clipboardCoordinator: ClipboardAccessCoordinator

    init(clipboardCoordinator: ClipboardAccessCoordinator) {
        self.clipboardCoordinator = clipboardCoordinator
        super.init()
    }

    func register(in registry: CommandRegistry) throws {
        for target in Self.shortcutTargets {
            try registry.register(CommandDescriptor(
                id: target.id, title: target.title,
                subtitle: String(localized: "Built-in Developer Tools"),
                keywords: ["developer", "tools", "开发者", "工具", target.id.rawValue]
            )) { [weak self] _ in
                self?.show(tool: Tool.allCases.first { $0.commandID == target.id })
            }
        }
    }

    func systemImage(for commandID: CommandID) -> String? {
        Self.shortcutTargets.contains { $0.id == commandID } ? "hammer" : nil
    }

    func generateUUIDs() {
        uuids = (0..<uuidCount).map { _ in UUID() }
        copyError = nil
    }

    func uuidText(_ uuid: UUID) -> String {
        uppercaseUUIDs ? uuid.uuidString : uuid.uuidString.lowercased()
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let success = pasteboard.setString(text, forType: .string)
        clipboardCoordinator.didWrite(changeCount: pasteboard.changeCount)
        copyError = success ? nil : String(localized: "Could not copy the result.")
    }

    func stop() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        uuids = []
        copyError = nil
        jsonSession.invalidate()
        jsonSession = DeveloperTextSession(kind: .json)
        urlSession.invalidate()
        base64Session.invalidate()
        urlSession = DeveloperTextSession(kind: .url)
        base64Session = DeveloperTextSession(kind: .base64)
        window?.contentView = nil
        window = nil
    }

    private func show(tool: Tool?) {
        if let tool { selection = tool }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "Developer Tools")
            window.minSize = NSSize(width: 760, height: 480)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: DeveloperToolsView(plugin: self))
            window.setFrameAutosaveName("builtin-developer-tools-window")
            window.center()
            self.window = window
        }
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

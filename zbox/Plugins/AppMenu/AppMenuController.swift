import AppKit
import ApplicationServices

nonisolated struct AppMenuItem: Identifiable {
    let id: UUID
    let title: String
    let path: String
    let shortcut: String
    let enabled: Bool
    let marked: Bool
}

nonisolated enum AppMenuError: LocalizedError {
    case permissionRequired, unavailable, unreadable, changed, tooLarge
    var errorDescription: String? {
        switch self {
        case .permissionRequired: String(localized: "Accessibility permission is required to search application menus.")
        case .unavailable: String(localized: "The original application is no longer available or has changed.")
        case .unreadable: String(localized: "This application's menu could not be read.")
        case .changed: String(localized: "The menu item is unavailable. Reopen menu search to refresh it.")
        case .tooLarge: String(localized: "The application menu is too large or is not responding.")
        }
    }
}

@MainActor
final class AppMenuController {
    private var elements: [UUID: AXUIElement] = [:]
    private var target: NSRunningApplication?

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    func clear() { elements = [:]; target = nil }

    func load(pid: pid_t?) async throws -> (String, [AppMenuItem]) {
        clear()
        guard AXIsProcessTrusted() else { throw AppMenuError.permissionRequired }
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier,
              let application = NSRunningApplication(processIdentifier: pid), !application.isTerminated else {
            throw AppMenuError.unavailable
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let menuValue = value(app, kAXMenuBarAttribute), CFGetTypeID(menuValue) == AXUIElementGetTypeID() else {
            throw AppMenuError.unreadable
        }
        let menu = unsafeDowncast(menuValue, to: AXUIElement.self)
        var pending: [(AXUIElement, [String])] = [(menu, [])]
        var items: [AppMenuItem] = []
        var loadedElements: [UUID: AXUIElement] = [:]
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var visited = 0
        while let (element, parents) = pending.popLast() {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline, visited < 3000 else { throw AppMenuError.tooLarge }
            visited += 1
            let title = value(element, kAXTitleAttribute) as? String ?? ""
            let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            let role = value(element, kAXRoleAttribute) as? String
            if role == kAXMenuItemRole, !title.isEmpty, children.isEmpty {
                let id = UUID()
                let modifiers = (value(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.uint32Value ?? 0
                let key = value(element, kAXMenuItemCmdCharAttribute) as? String ?? ""
                var shortcut = ""
                if !key.isEmpty {
                    if modifiers & 4 != 0 { shortcut += "⌃" }
                    if modifiers & 2 != 0 { shortcut += "⌥" }
                    if modifiers & 1 != 0 { shortcut += "⇧" }
                    if modifiers & 8 == 0 { shortcut += "⌘" }
                    shortcut += key.uppercased()
                }
                items.append(AppMenuItem(id: id, title: title, path: parents.joined(separator: " › "), shortcut: shortcut,
                    enabled: (value(element, kAXEnabledAttribute) as? Bool) == true,
                    marked: !(value(element, kAXMenuItemMarkCharAttribute) as? String ?? "").isEmpty))
                loadedElements[id] = element
            }
            let path = title.isEmpty ? parents : parents + [title]
            for child in children.reversed() { pending.append((child, path)) }
            if visited.isMultiple(of: 20) { await Task.yield() }
        }
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw AppMenuError.permissionRequired }
        target = application
        elements = loadedElements
        return (application.localizedName ?? "", items)
    }

    func execute(_ id: UUID) async throws {
        guard AXIsProcessTrusted() else { throw AppMenuError.permissionRequired }
        guard let target, let element = elements[id] else { throw AppMenuError.changed }
        do { try await ClipboardPasteController.activate(target) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AppMenuError.unavailable }
        try Task.checkCancellation()
        guard (value(element, kAXEnabledAttribute) as? Bool) == true,
              AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw AppMenuError.changed
        }
    }
}

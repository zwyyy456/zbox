import ZboxExtensionProtocol
import AppKit
import ApplicationServices

@MainActor
struct ExtensionHostAPI {
    let installation: ExtensionInstallation
    let data: ExtensionDataStore
    let coordinator: ClipboardAccessCoordinator
    let context: CommandContext

    static let capabilities = ["selection.read": "selection.read", "clipboard.read": "clipboard.read",
        "clipboard.write": "clipboard.write", "clipboard.paste": "clipboard.paste", "storage.get": "storage",
        "storage.set": "storage", "credentials.get": "credentials", "credentials.set": "credentials", "credentials.delete": "credentials"]

    func call(_ method: String, params: ExtensionValue, expectedClipboardCount: Int,
              isCurrent: @escaping @MainActor () -> Bool) async throws -> ExtensionValue {
        func check() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw ExtensionFailure("The extension event has ended.") }
        }
        try check()
        if method != "settings.get" {
            guard let capability = Self.capabilities[method], installation.grants.contains(capability),
                  (installation.manifest.capabilities ?? []).contains(capability) else { throw ExtensionFailure("Host capability not granted.") }
        }
        func text(_ key: String) throws -> String {
            guard let text = params[key]?.string, text.utf8.count <= 1_048_576 else { throw ExtensionFailure("Missing or oversized text parameter.") }
            return text
        }
        switch method {
        case "selection.read":
            let result = try await SelectedTextReader.read(targetPID: context.frontmostApplicationPID)
            try check(); return .string(result)
        case "clipboard.read":
            guard let value = NSPasteboard.general.string(forType: .string) else { return .null }
            guard value.utf8.count <= 1_048_576 else { throw ExtensionFailure("Clipboard text exceeds 1 MiB.") }
            return .string(value)
        case "clipboard.write", "clipboard.paste":
            let value = try text("text")
            var target: NSRunningApplication?
            if method == "clipboard.paste" {
                guard AXIsProcessTrusted() else { throw ClipboardPasteError.permissionRequired }
                guard let pid = context.frontmostApplicationPID, let app = NSRunningApplication(processIdentifier: pid) else { throw ClipboardPasteError.targetUnavailable }
                try await ClipboardPasteController.activate(app); target = app
            }
            try check()
            let board = NSPasteboard.general
            guard board.changeCount == expectedClipboardCount else { throw ExtensionFailure("The clipboard changed after this action. Try again.") }
            if target != nil, !AXIsProcessTrusted() { throw ClipboardPasteError.permissionRequired }
            board.prepareForNewContents(with: .currentHostOnly)
            let success = board.setString(value, forType: .string)
            coordinator.didWrite(changeCount: board.changeCount)
            guard success else { throw ExtensionFailure("Could not copy the result.") }
            if let target { try ClipboardPasteController.paste(into: target) }
            return .null
        case "settings.get":
            let stored = try await data.settings()
            try check()
            let values = (installation.manifest.settings ?? []).filter { $0.type != "secret" }.reduce(into: [String: ExtensionValue]()) {
                $0[$1.id] = .string(stored[$1.id] ?? $1.defaultValue ?? "")
            }
            return .object(values)
        case "storage.get", "storage.set":
            let key = try text("key")
            if method == "storage.set", params["value"] == nil { throw ExtensionFailure("Missing storage value.") }
            let value = try await data.storage(key, value: method == "storage.set" ? params["value"] : nil)
            try check(); return value
        case "credentials.get", "credentials.set", "credentials.delete":
            let key = try text("key")
            let value = try await data.credential(key, value: method == "credentials.set" ? text("value") : nil, delete: method == "credentials.delete")
            try check(); return value.map(ExtensionValue.string) ?? .null
        default: throw ExtensionFailure("Unknown host method.")
        }
    }
}

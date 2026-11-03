import AppKit
import ApplicationServices
import Carbon

nonisolated enum SelectedTextError: LocalizedError {
    case permissionRequired, targetChanged, protectedText, unavailable, tooLarge
    var errorDescription: String? {
        switch self {
        case .permissionRequired: String(localized: "Reading selected text requires Accessibility permission.")
        case .targetChanged: String(localized: "The original application is no longer available or has changed.")
        case .protectedText: String(localized: "Protected text cannot be read.")
        case .unavailable: String(localized: "Select text in an application that exposes its selection to Accessibility.")
        case .tooLarge: String(localized: "Input exceeds the 1 MiB limit.")
        }
    }
}

@MainActor
enum SelectedTextReader {
    static func read(targetPID: pid_t?) async throws -> String {
        guard AXIsProcessTrusted() else { throw SelectedTextError.permissionRequired }
        guard !IsSecureEventInputEnabled() else { throw SelectedTextError.protectedText }
        guard let targetPID, let app = NSRunningApplication(processIdentifier: targetPID) else {
            throw SelectedTextError.targetChanged
        }
        do { try await ClipboardPasteController.activate(app) }
        catch is CancellationError { throw CancellationError() }
        catch { throw SelectedTextError.targetChanged }
        try Task.checkCancellation()
        let application = AXUIElementCreateApplication(targetPID)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let focusedValue = value(application, kAXFocusedUIElementAttribute),
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { throw SelectedTextError.unavailable }
        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
        var parent: AXUIElement? = element
        var ancestors = Set<ObjectIdentifier>()
        while let current = parent {
            guard ancestors.insert(ObjectIdentifier(current)).inserted else { throw SelectedTextError.unavailable }
            if value(current, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { throw SelectedTextError.protectedText }
            if let next = value(current, kAXParentAttribute), CFGetTypeID(next) == AXUIElementGetTypeID() {
                parent = unsafeDowncast(next, to: AXUIElement.self)
            } else { parent = nil }
        }
        guard let text = value(element, kAXSelectedTextAttribute) as? String, !text.isEmpty else {
            throw SelectedTextError.unavailable
        }
        guard text.utf8.count <= 1_048_576 else { throw SelectedTextError.tooLarge }
        guard !IsSecureEventInputEnabled(), AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            throw SelectedTextError.targetChanged
        }
        try Task.checkCancellation()
        return text
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
}

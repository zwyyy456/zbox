import AppKit
import ApplicationServices

@MainActor
final class AccessibilityAuthorization {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

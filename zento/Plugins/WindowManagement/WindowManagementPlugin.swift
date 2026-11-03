import Foundation
import Observation

@MainActor
@Observable
final class WindowManagementPlugin {
    private static let enabledKey = "window-management.enabled"

    private let defaults: UserDefaults
    private let hotkeyRegistrar: any HotkeyRegistering
    private let controller: AccessibilityWindowController
    private let isAccessibilityTrusted: @MainActor () -> Bool

    private(set) var isEnabled: Bool
    private(set) var isRunning = false
    private(set) var statusMessage: String?

    init(
        defaults: UserDefaults = .standard,
        hotkeyRegistrar: any HotkeyRegistering,
        controller: AccessibilityWindowController = AccessibilityWindowController(),
        isAccessibilityTrusted: @escaping @MainActor () -> Bool
    ) {
        self.defaults = defaults
        self.hotkeyRegistrar = hotkeyRegistrar
        self.controller = controller
        self.isAccessibilityTrusted = isAccessibilityTrusted
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func register(in registry: CommandRegistry) throws {
        try WindowCommands.registerAll(in: registry, controller: controller) { [weak self] in
            self?.isRunning == true
        }
    }

    func start() {
        reconcileAuthorization()
        isRunning = isEnabled
    }

    func stop() {
        isRunning = false
        for target in WindowCommands.shortcutTargets {
            hotkeyRegistrar.unregister(id: target.id.rawValue)
        }
    }

    func setEnabled(_ enabled: Bool, registerHotkeys: () throws -> Void) {
        guard enabled else {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledKey)
            stop()
            statusMessage = nil
            return
        }
        guard isAccessibilityTrusted() else {
            reconcileAuthorization()
            statusMessage = String(localized: "Accessibility permission is required to enable Window Management.")
            return
        }
        guard !isRunning else { return }

        isRunning = true
        do {
            try registerHotkeys()
            isEnabled = true
            defaults.set(true, forKey: Self.enabledKey)
            statusMessage = nil
        } catch {
            isRunning = false
            statusMessage = error.localizedDescription
        }
    }

    func reconcileAuthorization() {
        guard !isAccessibilityTrusted(), isEnabled || isRunning else { return }
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
        stop()
        statusMessage = String(localized: "Accessibility-dependent features were disabled. Re-enable them after granting permission.")
    }

    func hotkeyRequests(
        for hotkeys: [CommandID: Hotkey],
        execute: @escaping @MainActor (CommandID) -> Void
    ) -> [HotkeyRegistrationRequest] {
        guard isRunning, isAccessibilityTrusted() else { return [] }
        return WindowCommands.shortcutTargets.compactMap { target in
            guard let hotkey = hotkeys[target.id] else { return nil }
            return HotkeyRegistrationRequest(
                id: target.id.rawValue,
                hotkey: hotkey,
                label: HotkeyFormatter.displayName(for: hotkey)
            ) {
                execute(target.id)
            }
        }
    }
}

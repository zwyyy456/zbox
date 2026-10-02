import Foundation
import Testing
@testable import zbox

@MainActor
struct WindowManagementPluginTests {
    @Test
    func disablingAndRevokingPermissionOnlyStopWindowShortcuts() throws {
        let suite = "WindowManagementPluginTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let permission = WindowPermissionState(isTrusted: true)
        let registrar = WindowHotkeyRegistrar()
        let plugin = WindowManagementPlugin(
            defaults: defaults,
            hotkeyRegistrar: registrar,
            isAccessibilityTrusted: { permission.isTrusted }
        )
        let hotkeys = [WindowCommands.leftHalfID: Hotkey.defaultRootSearch]
        var executed: CommandID?
        #expect(!plugin.isEnabled)
        #expect(plugin.hotkeyRequests(for: hotkeys) { _ in }.isEmpty)

        plugin.setEnabled(true) {}
        let request = try #require(plugin.hotkeyRequests(for: hotkeys) { executed = $0 }.first)
        request.action()
        #expect(executed == WindowCommands.leftHalfID)
        #expect(defaults.bool(forKey: "window-management.enabled"))

        permission.isTrusted = false
        plugin.reconcileAuthorization()
        #expect(!plugin.isEnabled)
        #expect(!plugin.isRunning)
        #expect(!defaults.bool(forKey: "window-management.enabled"))
        #expect(Set(registrar.removed) == Set(WindowCommands.shortcutTargets.map(\.id.rawValue)))
        permission.isTrusted = true
        plugin.reconcileAuthorization()
        #expect(plugin.hotkeyRequests(for: hotkeys) { _ in }.isEmpty)

        plugin.setEnabled(true) {}
        plugin.setEnabled(false) { Issue.record("Disabling must not register shortcuts") }
        #expect(!plugin.isEnabled)
        #expect(plugin.hotkeyRequests(for: hotkeys) { _ in }.isEmpty)
    }

    @Test
    func permissionAndRegistrationFailuresDoNotEnablePlugin() throws {
        let suite = "WindowManagementPluginTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let permission = WindowPermissionState(isTrusted: false)
        let plugin = WindowManagementPlugin(
            defaults: defaults,
            hotkeyRegistrar: WindowHotkeyRegistrar(),
            isAccessibilityTrusted: { permission.isTrusted }
        )
        plugin.setEnabled(true) { Issue.record("Missing permission must not register shortcuts") }
        #expect(!plugin.isEnabled)
        #expect(plugin.statusMessage != nil)

        permission.isTrusted = true
        plugin.setEnabled(true) { throw RegistrationFailure.failed }
        #expect(!plugin.isRunning)
        #expect(!plugin.isEnabled)
        #expect(!defaults.bool(forKey: "window-management.enabled"))
        #expect(plugin.statusMessage != nil)
    }

    @Test
    func stopPreservesPreferenceButPreventsCommandExecution() async throws {
        let suite = "WindowManagementPluginTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "window-management.enabled")
        let plugin = WindowManagementPlugin(
            defaults: defaults,
            hotkeyRegistrar: WindowHotkeyRegistrar(),
            isAccessibilityTrusted: { true }
        )
        let registry = CommandRegistry()
        try plugin.register(in: registry)
        plugin.start()
        #expect(plugin.isRunning)
        plugin.stop()
        #expect(defaults.bool(forKey: "window-management.enabled"))
        #expect(registry.descriptors.count == 3)
        for source in [CommandSource.rootSearch, .directHotkey] {
            await #expect(throws: WindowManagementError.disabled) {
                try await registry.execute(
                    WindowCommands.leftHalfID,
                    context: CommandContext(source: source, frontmostApplicationPID: nil)
                )
            }
        }
        plugin.start()
        #expect(plugin.isRunning)
    }
}

@MainActor
private final class WindowHotkeyRegistrar: HotkeyRegistering {
    var removed: [String] = []
    func replace(ids: Set<String>, with requests: [HotkeyRegistrationRequest]) throws {}
    func setSuspended(_ isSuspended: Bool) throws {}
    func unregisterAll() { Issue.record("Plugin must only unregister its own shortcuts") }
    func unregister(id: String) { removed.append(id) }
}

private enum RegistrationFailure: Error { case failed }

@MainActor
private final class WindowPermissionState {
    var isTrusted: Bool
    init(isTrusted: Bool) { self.isTrusted = isTrusted }
}

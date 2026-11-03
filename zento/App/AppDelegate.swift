import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        environment.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        environment.reconcileAccessibilityDependentFeatures()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard environment.scriptCommandsPlugin.isRunning || environment.extensionManager.hasRunningTasks else { return .terminateNow }
        environment.stop()
        Task {
            await environment.scriptCommandsPlugin.waitForStop()
            await environment.extensionManager.waitForStop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }
}

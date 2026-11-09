import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var isPreparingToTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        environment.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.showRootSearch()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        environment.reconcileAccessibilityDependentFeatures()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isPreparingToTerminate { return .terminateLater }
        guard environment.screenshotPlugin.hasRecordingSession || environment.scriptCommandsPlugin.isRunning
                || environment.extensionManager.hasRunningTasks else { return .terminateNow }
        isPreparingToTerminate = true
        Task {
            guard await environment.screenshotPlugin.prepareForShutdown() else {
                isPreparingToTerminate = false
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            environment.stop()
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

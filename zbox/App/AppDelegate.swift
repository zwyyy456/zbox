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

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }
}

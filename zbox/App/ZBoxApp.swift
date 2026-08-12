import SwiftUI

@main
struct ZBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("zbox", systemImage: "shippingbox") {
            MenuBarView(environment: appDelegate.environment)
        }

        Settings {
            SettingsView(environment: appDelegate.environment)
        }
    }
}

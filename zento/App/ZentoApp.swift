import AppKit
import SwiftUI

@main
struct ZentoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearance.show-menu-bar-icon") private var showsMenuBarIcon = true

    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon")!.copy() as! NSImage
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { showsMenuBarIcon },
            set: { visible in
                // AppKit reports insertion state even when unchanged. Writing that
                // back to AppStorage repeatedly invalidates SwiftUI's main menu.
                if showsMenuBarIcon != visible { showsMenuBarIcon = visible }
            }
        )) {
            MenuBarView(environment: appDelegate.environment)
        } label: {
            Image(nsImage: Self.menuBarIcon)
                .renderingMode(.template)
                .accessibilityLabel("Zento")
        }

        Settings {
            SettingsView(environment: appDelegate.environment)
        }
        .windowResizability(.contentMinSize)
        .commands {
            SettingsSceneCommands(opener: appDelegate.environment.settingsWindowOpener)
        }
    }
}

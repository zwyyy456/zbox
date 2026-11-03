import AppKit
import SwiftUI

@main
struct ZentoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private static let menuBarIcon: NSImage = {
        // MenuBarExtra uses the NSImage's point size for its native status item.
        let image = NSImage(named: "MenuBarIcon")!.copy() as! NSImage
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(environment: appDelegate.environment)
        } label: {
            SettingsMenuBarLabel(image: Self.menuBarIcon, opener: appDelegate.environment.settingsWindowOpener)
        }

        Settings {
            SettingsView(environment: appDelegate.environment)
        }
        .windowResizability(.contentMinSize)
    }
}

/// The status item exists before its menu is opened, so commands can open Settings too.
private struct SettingsMenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings
    let image: NSImage
    let opener: SettingsWindowOpener

    var body: some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .accessibilityLabel("Zento")
            .onAppear {
                opener.bindOpenAction { [openSettings] in openSettings() }
            }
    }
}

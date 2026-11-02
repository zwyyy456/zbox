import AppKit
import SwiftUI

@main
struct ZBoxApp: App {
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
            Image(nsImage: Self.menuBarIcon)
                .renderingMode(.template)
                .accessibilityLabel("zbox")
        }

        Settings {
            SettingsView(environment: appDelegate.environment)
        }
        .windowResizability(.contentMinSize)
    }
}

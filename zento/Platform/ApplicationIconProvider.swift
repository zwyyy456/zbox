import AppKit

@MainActor
final class ApplicationIconProvider {
    private var icons: [URL: NSImage] = [:]

    func icon(for applicationURL: URL) -> NSImage {
        if let icon = icons[applicationURL] {
            return icon
        }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icons[applicationURL] = icon
        return icon
    }
}

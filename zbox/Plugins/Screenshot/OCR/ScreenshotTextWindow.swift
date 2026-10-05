import SwiftUI

@MainActor
final class ScreenshotTextWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var document: ScreenshotDocument?

    func show(image: CGImage, copy: @escaping (String) -> Void) {
        close()
        let document = ScreenshotDocument(image: image)
        self.document = document
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 480),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: "Recognized Text")
        window.minSize = CGSize(width: 620, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ScreenshotOCRView(document: document, copy: copy))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        document.ocr.run(image: image, edit: document.edit)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        document?.ocr.invalidate()
        document = nil
        window?.contentView = nil
        window = nil
    }
}

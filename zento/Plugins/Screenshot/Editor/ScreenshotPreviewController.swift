import AppKit
import SwiftUI

@MainActor
final class ScreenshotPreviewController: NSObject, NSWindowDelegate {
    private var onClose: (() -> Void)?
    private var panel: NSPanel?
    private(set) var screen: NSScreen?

    func show(plugin: ScreenshotPlugin, image: CGImage, on screen: NSScreen) {
        close()
        self.screen = screen
        let scale = min(360 / CGFloat(image.width), 280 / CGFloat(image.height), 1)
        let imageSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let width = max(plugin.hosting.selected == nil ? 200 : 216, imageSize.width)
        let frame = screen.visibleFrame
        let panel = NSPanel(contentRect: CGRect(x: frame.maxX - width - 20, y: frame.minY + 20,
                                               width: width, height: imageSize.height + 44),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: "Screenshot Preview")
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        onClose = { [weak plugin] in plugin?.dismissPreview() }
        panel.contentView = NSHostingView(rootView: ScreenshotPreviewView(plugin: plugin, image: image, imageSize: imageSize))
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    func close() {
        onClose = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        screen = nil
    }
}

private struct ScreenshotPreviewView: View {
    let plugin: ScreenshotPlugin
    let image: CGImage
    let imageSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Button(action: plugin.editPreview) {
                Image(decorative: image, scale: 1).resizable()
                    .frame(width: imageSize.width, height: imageSize.height)
            }.buttonStyle(.plain).help("Open Editor").accessibilityLabel("Open Editor")
                .frame(maxWidth: .infinity)
            Divider()
            HStack(spacing: plugin.hosting.selected == nil && !plugin.isUploading ? 8 : 4) {
                Group {
                    action("Open Editor", symbol: "pencil", perform: plugin.editPreview)
                    action("Copy Image", symbol: "doc.on.doc") { plugin.copyImage(closesEditor: true) }
                    action("Save…", symbol: "square.and.arrow.down") { plugin.saveImage(closesEditor: true) }
                    action("Pin Image", symbol: "pin") { plugin.pinImage(closesEditor: true) }
                    action("Recognize Text", symbol: "text.viewfinder", perform: plugin.recognizePreview)
                }.disabled(plugin.isUploading)
                if plugin.isUploading {
                    action("Cancel Upload", symbol: "xmark.circle", perform: plugin.cancelUpload)
                } else if plugin.hosting.selected != nil {
                    action("Upload", symbol: "square.and.arrow.up") { plugin.uploadImage(closesEditor: true) }
                }
            }.frame(maxWidth: .infinity).frame(height: 43)
                .background(.bar).disabled(plugin.isExporting)
        }
        .frame(minWidth: plugin.hosting.selected == nil && !plugin.isUploading ? 200 : 216)
        .overlay(alignment: .top) {
            if plugin.isUploading {
                VStack(spacing: 4) {
                    Text(plugin.uploadHostName).font(.caption).lineLimit(1)
                    ProgressView(value: plugin.uploadProgress)
                }.padding(8).background(.regularMaterial)
            } else if plugin.isExporting {
                ProgressView().controlSize(.small).padding(8).background(.regularMaterial)
            } else if let message = plugin.statusMessage {
                HStack {
                    Text(message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    if plugin.uploadedURL != nil {
                        action("Copy Link", symbol: "link", perform: plugin.copyUploadedLink)
                    }
                }.padding(8).background(.regularMaterial)
            }
        }.onExitCommand(perform: plugin.dismissPreview)
    }

    private func action(_ title: LocalizedStringKey, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 30, height: 30)
        }.buttonStyle(.borderless).help(Text(title)).accessibilityLabel(Text(title))
    }
}

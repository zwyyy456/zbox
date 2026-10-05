import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScreenshotPinController {
    private var pins: [ScreenshotPin] = []
    private var hidden = false

    func add(_ image: CGImage, coordinator: ClipboardAccessCoordinator, recognize: @escaping (CGImage) -> Void) throws {
        let bytes = image.bytesPerRow * image.height
        guard pins.count < 10, pins.reduce(bytes, { $0 + $1.image.bytesPerRow * $1.image.height }) <= 256 * 1_024 * 1_024 else {
            throw ScreenshotError.pinLimit
        }
        let pin = ScreenshotPin(image: image, coordinator: coordinator, recognize: recognize) { [weak self] id in
            self?.pins.removeAll { $0.id == id }
        }
        pins.append(pin)
        hidden = false
        for pin in pins { pin.window.orderFrontRegardless() }
    }

    func toggleVisibility() {
        hidden.toggle()
        for pin in pins {
            if hidden { pin.window.orderOut(nil) } else { pin.window.orderFrontRegardless() }
        }
    }

    func closeAll() {
        for pin in pins { pin.window.close() }
        pins = []
        hidden = false
    }
}

@MainActor @Observable
private final class ScreenshotPin: NSObject, NSWindowDelegate, Identifiable {
    let id = UUID()
    let image: CGImage
    let window: ScreenshotPinPanel
    var opacity = 1.0 { didSet { window.alphaValue = opacity } }
    var error: String?
    private let coordinator: ClipboardAccessCoordinator
    private let onClose: (UUID) -> Void
    let recognize: (CGImage) -> Void
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    private var defaultSize: CGSize = .zero

    init(image: CGImage, coordinator: ClipboardAccessCoordinator, recognize: @escaping (CGImage) -> Void,
         onClose: @escaping (UUID) -> Void) {
        self.image = image
        self.coordinator = coordinator
        self.recognize = recognize
        self.onClose = onClose
        window = ScreenshotPinPanel(contentRect: .zero, styleMask: [.borderless, .resizable, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        super.init()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentAspectRatio = CGSize(width: image.width, height: image.height)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        let scale = min(1 / (screen?.backingScaleFactor ?? 1), frame.width * 0.7 / CGFloat(image.width), frame.height * 0.7 / CGFloat(image.height))
        defaultSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        window.setFrame(CGRect(x: frame.midX - defaultSize.width / 2, y: frame.midY - defaultSize.height / 2,
                               width: defaultSize.width, height: defaultSize.height), display: false)
        window.contentView = NSHostingView(rootView: ScreenshotPinView(pin: self))
    }

    func resize(_ factor: CGFloat) {
        let frame = window.frame
        let size = factor == 0 ? defaultSize : CGSize(width: frame.width * factor, height: frame.height * factor)
        guard size.width >= 40, size.height >= 40,
              size.width <= CGFloat(image.width) * 4, size.height <= CGFloat(image.height) * 4 else { return }
        window.setFrame(CGRect(origin: frame.origin, size: size), display: true)
    }

    func copy() {
        export { [weak self] data in
            let board = NSPasteboard.general
            board.prepareForNewContents(with: .currentHostOnly)
            let copied = board.setData(data, forType: .png)
            self?.coordinator.didWrite(changeCount: board.changeCount)
            if !copied { throw ScreenshotError.exportFailed }
        }
    }

    func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Pinned Image.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        export { try $0.write(to: url, options: .atomic) }
    }

    private func export(_ completion: @escaping @MainActor (Data) throws -> Void) {
        exportTask?.cancel()
        error = nil
        let image = image
        exportTask = Task { [weak self] in
            do {
                let data = try await ScreenshotRenderer.encode(image, format: .png)
                guard !Task.isCancelled, let self else { return }
                try completion(data)
                exportTask = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.error = String(localized: "Could not export the pinned image.")
                exportTask = nil
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        exportTask?.cancel()
        exportTask = nil
        window.contentView = nil
        onClose(id)
    }
}

private final class ScreenshotPinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

private struct ScreenshotPinView: View {
    @Bindable var pin: ScreenshotPin
    @State private var hovering = false

    var body: some View {
        Image(decorative: pin.image, scale: 1).resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .overlay(alignment: .topTrailing) {
                if hovering {
                    HStack(spacing: 6) {
                        Button("Copy", systemImage: "doc.on.doc", action: pin.copy)
                        Menu("Image Actions", systemImage: "ellipsis") { actions }
                        Button("Close", systemImage: "xmark") { pin.window.close() }
                    }.labelStyle(.iconOnly).padding(6).background(.regularMaterial)
                }
            }
            .overlay(alignment: .bottom) {
                if let error = pin.error { Text(error).font(.caption).padding(6).background(.regularMaterial) }
            }
            .onHover { hovering = $0 }
            .contextMenu { actions }
            .accessibilityLabel("Pinned Image")
    }

    @ViewBuilder private var actions: some View {
        Button("Copy Image", action: pin.copy)
        Button("Save…", action: pin.save)
        Button("Recognize Text") { pin.recognize(pin.image) }
        Divider()
        Button("Zoom In") { pin.resize(1.25) }
        Button("Zoom Out") { pin.resize(0.8) }
        Button("Reset Size") { pin.resize(0) }
        Menu("Opacity") {
            ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { opacity in
                Button(opacity.formatted(.percent)) { pin.opacity = opacity }
            }
        }
        Divider()
        Button("Close") { pin.window.close() }
    }
}

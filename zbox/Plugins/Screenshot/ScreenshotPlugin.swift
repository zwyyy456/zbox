import AppKit
import Observation
import SwiftUI
import ScreenCaptureKit

@MainActor
@Observable
final class ScreenshotPlugin {
    static var shortcutTargets: [CommandShortcutTarget] {
        ScreenshotMode.allCases.map { CommandShortcutTarget(id: $0.commandID, title: $0.title) }
    }
    private let defaults: UserDefaults
    let clipboardCoordinator: ClipboardAccessCoordinator
    private let selection = ScreenshotSelection()
    private var captureTask: Task<Void, Never>?
    private var captureID: UUID?
    @ObservationIgnored private var window: ScreenshotWindow?
    private(set) var isEnabled: Bool
    private(set) var statusMessage: String?
    private(set) var image: CGImage?

    init(defaults: UserDefaults = .standard, clipboardCoordinator: ClipboardAccessCoordinator) {
        self.defaults = defaults
        self.clipboardCoordinator = clipboardCoordinator
        isEnabled = defaults.bool(forKey: "plugin.screenshot.enabled")
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        for mode in ScreenshotMode.allCases {
            try registry.register(CommandDescriptor(id: mode.commandID, title: mode.title,
                subtitle: String(localized: "Screenshot"), keywords: ["screenshot", "capture", "截图", "截屏"])) { [weak self] _ in
                guard let self else { return }
                guard isEnabled else { try openSettings(); return }
                capture(mode)
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "plugin.screenshot.enabled")
        if !enabled { stop() }
    }

    func stop() {
        cancelCapture()
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        image = nil
    }

    func cancelCapture() {
        captureID = nil
        captureTask?.cancel()
        captureTask = nil
        selection.close()
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func capture(_ mode: ScreenshotMode) {
        cancelCapture()
        window?.orderOut(nil)
        statusMessage = nil
        let id = UUID()
        captureID = id
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        captureTask = Task { [weak self] in
            do {
                let content = try await ScreenshotCapture.content()
                try Task.checkCancellation()
                guard let self, captureID == id else { return }
                if mode == .screen {
                    guard let screen else { throw ScreenshotError.unavailable }
                    finishCapture(content: content, screen: screen, area: nil, selectedWindow: nil, id: id)
                } else {
                    selection.show(mode: mode, windows: content.windows) { [weak self] screen, area, selectedWindow in
                        self?.finishCapture(content: content, screen: screen, area: area, selectedWindow: selectedWindow, id: id)
                    } cancelled: { [weak self] in self?.cancelCapture() }
                }
            } catch {
                guard !Task.isCancelled, self?.captureID == id else { return }
                self?.report(error)
            }
        }
    }

    private func finishCapture(content: SCShareableContent, screen: NSScreen, area: CGRect?, selectedWindow: SCWindow?, id: UUID) {
        selection.close()
        captureTask = Task { [weak self] in
            do {
                let image = try await ScreenshotCapture.image(content: content, screen: screen, area: area, window: selectedWindow)
                try Task.checkCancellation()
                guard let self, captureID == id, isEnabled else { return }
                self.image = image
                show(on: screen)
            } catch {
                guard !Task.isCancelled, self?.captureID == id else { return }
                self?.report(error)
            }
        }
    }

    private func report(_ error: Error) {
        statusMessage = (error as? ScreenshotError)?.localizedDescription ?? ScreenshotError.captureFailed.localizedDescription
        show(on: NSScreen.main)
    }

    private func show(on screen: NSScreen?) {
        if window == nil {
            let panel = ScreenshotWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = String(localized: "Screenshot")
            panel.minSize = CGSize(width: 580, height: 400)
            panel.isReleasedWhenClosed = false
            panel.didClose = { [weak self] in self?.stop() }
            panel.contentView = NSHostingView(rootView: ScreenshotEditorView(plugin: self))
            window = panel
        }
        if let screen {
            let frame = screen.visibleFrame
            window?.setFrameOrigin(CGPoint(x: frame.midX - (window?.frame.width ?? 0) / 2,
                                           y: frame.midY - (window?.frame.height ?? 0) / 2))
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

final class ScreenshotWindow: NSWindow {
    var didClose: (() -> Void)?
    override func close() { super.close(); didClose?() }
}

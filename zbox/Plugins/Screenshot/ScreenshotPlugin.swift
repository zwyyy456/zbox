import AppKit
import Observation
import SwiftUI
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class ScreenshotPlugin {
    private enum CapturePurpose { case edit, text, pin }
    private enum PinCommand: String, CaseIterable {
        case capture, clipboard, toggle, close
        var id: CommandID { CommandID("screenshot.pin.\(rawValue)") }
        var title: String {
            switch self {
            case .capture: String(localized: "Capture & Pin")
            case .clipboard: String(localized: "Pin Clipboard Image")
            case .toggle: String(localized: "Show / Hide Pinned Images")
            case .close: String(localized: "Close All Pinned Images")
            }
        }
    }
    private var pinGeneration = 0
    private var pinImportTask: Task<Void, Never>?
    static let textCommandID = CommandID("screenshot.ocr")
    private let textWindow = ScreenshotTextWindow()
    private let pins = ScreenshotPinController()

    static var shortcutTargets: [CommandShortcutTarget] {
        ScreenshotMode.allCases.map { CommandShortcutTarget(id: $0.commandID, title: $0.title) }
        + [CommandShortcutTarget(id: textCommandID, title: String(localized: "Capture Text"))]
        + PinCommand.allCases.map { CommandShortcutTarget(id: $0.id, title: $0.title) }
    }
    let hosting: ScreenshotHostingSettings
    private let defaults: UserDefaults
    let clipboardCoordinator: ClipboardAccessCoordinator
    private let selection = ScreenshotSelection()
    private var captureTask: Task<Void, Never>?
    private var captureID: UUID?
    @ObservationIgnored private var window: ScreenshotWindow?
    private(set) var isEnabled: Bool
    private(set) var statusMessage: String?
    private(set) var needsScreenRecordingPermission = false
    private(set) var document: ScreenshotDocument?
    private(set) var isExporting = false
    var format: ScreenshotFormat {
        didSet { defaults.set(format.rawValue, forKey: "plugin.screenshot.format") }
    }
    private var exportTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    private var uploadID: UUID?
    private var pendingUpload: ScreenshotUploadSnapshot?
    var canRetryUpload: Bool { pendingUpload != nil && !isUploading && !isExporting }
    private(set) var isUploading = false
    private(set) var uploadProgress = 0.0
    private(set) var uploadedURL: URL?
    private(set) var uploadHostName = ""

    init(defaults: UserDefaults = .standard, clipboardCoordinator: ClipboardAccessCoordinator) {
        self.defaults = defaults
        hosting = ScreenshotHostingSettings(defaults: defaults)
        format = ScreenshotFormat(rawValue: defaults.string(forKey: "plugin.screenshot.format") ?? "") ?? .png
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
        try registry.register(CommandDescriptor(id: Self.textCommandID, title: String(localized: "Capture Text"),
            subtitle: String(localized: "Screenshot"), keywords: ["ocr", "text", "识别文字", "截图文字"])) { [weak self] _ in
            guard let self else { return }
            guard isEnabled else { try openSettings(); return }
            capture(.area, purpose: .text)
        }
        for command in PinCommand.allCases {
            try registry.register(CommandDescriptor(id: command.id, title: command.title,
                subtitle: String(localized: "Screenshot"), keywords: ["pin", "image", "贴图", "悬浮", "图片"])) { [weak self] _ in
                guard let self else { return }
                guard isEnabled else { try openSettings(); return }
                switch command {
                case .capture: capture(.area, purpose: .pin)
                case .clipboard: try pinClipboard()
                case .toggle: pins.toggleVisibility()
                case .close:
                    pinGeneration += 1
                    pinImportTask?.cancel()
                    pins.closeAll()
                }
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "plugin.screenshot.enabled")
        if !enabled { stop() }
    }

    func stop() {
        pinGeneration += 1
        pinImportTask?.cancel()
        pinImportTask = nil
        pins.closeAll()
        textWindow.close()
        closeEditor()
    }

    private func closeEditor() {
        cancelCapture()
        document?.ocr.invalidate()
        cancelUpload()
        uploadedURL = nil
        pendingUpload = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
        document = nil
    }

    func cancelCapture() {
        captureID = nil
        captureTask?.cancel()
        captureTask = nil
        selection.close()
    }

    private func pinClipboard() throws {
        let data = try ScreenshotPinClipboard.read()
        pinImportTask?.cancel()
        pinImportTask = Task { [weak self] in
            do {
                let image = try await ScreenshotPinClipboard.decode(data)
                guard !Task.isCancelled, let self, isEnabled else { return }
                try addPin(image)
                pinImportTask = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                pinImportTask = nil
                report(error)
            }
        }
    }

    func pinImage() {
        guard let document, !isExporting, !isUploading else { return }
        isExporting = true
        let edit = document.edit
        let generation = pinGeneration
        exportTask = Task { [weak self] in
            do {
                let image = try await ScreenshotRenderer.flattened(image: document.image, edit: edit)
                guard !Task.isCancelled, let self, self.document === document else { return }
                if pinGeneration == generation { try addPin(image) }
                isExporting = false
                exportTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.document === document else { return }
                statusMessage = error.localizedDescription
                isExporting = false
                exportTask = nil
            }
        }
    }

    private func addPin(_ image: CGImage) throws {
        try pins.add(image, coordinator: clipboardCoordinator) { [weak self] image in
            self?.textWindow.show(image: image) { [weak self] in self?.copyText($0) }
        }
    }

    func copyText(_ text: String) {
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        let copied = board.setString(text, forType: .string)
        clipboardCoordinator.didWrite(changeCount: board.changeCount)
        statusMessage = copied ? String(localized: "Text copied.") : String(localized: "Could not copy the result.")
    }

    func copyImage() {
        export(format: .png) { [weak self] data in
            let board = NSPasteboard.general
            board.prepareForNewContents(with: .currentHostOnly)
            defer { self?.clipboardCoordinator.didWrite(changeCount: board.changeCount) }
            guard board.setData(data, forType: .png) else { throw ScreenshotError.exportFailed }
            self?.statusMessage = String(localized: "Image copied.")
        }
    }

    func saveImage() {
        guard let document, !isExporting, !isUploading else { return }
        let selectedFormat = format
        let panel = NSSavePanel()
        panel.allowedContentTypes = [selectedFormat.type]
        panel.nameFieldStringValue = "Screenshot-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))-\(UUID().uuidString.prefix(8)).\(format.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url, self.document === document else { return }
        export(format: selectedFormat) { [weak self] data in
            try data.write(to: url, options: .atomic)
            self?.statusMessage = String(localized: "Image saved.")
        }
    }

    private func export(format: ScreenshotFormat, completed: @escaping @MainActor (Data) throws -> Void) {
        guard let document, !isExporting, !isUploading else { return }
        isExporting = true
        statusMessage = nil
        let edit = document.edit
        exportTask = Task { [weak self] in
            do {
                let data = try await ScreenshotRenderer.export(image: document.image, edit: edit, format: format)
                try Task.checkCancellation()
                guard let self, self.document === document else { return }
                try completed(data)
                isExporting = false
                exportTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.document === document else { return }
                isExporting = false
                exportTask = nil
                statusMessage = ScreenshotError.exportFailed.localizedDescription
            }
        }
    }

    var completionTitle: String {
        hosting.automaticallyUpload ? String(localized: "Done & Upload") : String(localized: "Done & Copy")
    }

    func finishEditing() {
        if hosting.automaticallyUpload { uploadImage() } else { copyImage() }
    }

    func uploadImage() {
        guard let document, !isUploading, !isExporting else { return }
        beginUpload(image: document.image, edit: document.edit, format: format, copiesLink: true)
    }

    func uploadTestImage() {
        guard !isUploading, !isExporting else { return }
        guard let context = CGContext(data: nil, width: 160, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
        guard let image = context.makeImage() else { return }
        beginUpload(image: image, edit: ScreenshotEdit(crop: CGRect(x: 0, y: 0, width: 160, height: 80)), format: .png, copiesLink: false)
    }

    func cancelUpload() {
        if isUploading { statusMessage = String(localized: "Upload cancelled. The host may already have received the image.") }
        uploadID = nil
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false
        uploadProgress = 0
    }

    func copyUploadedLink() {
        guard let uploadedURL else { return }
        if ScreenshotClipboard.copyLink(uploadedURL, format: hosting.linkFormat, to: .general, coordinator: clipboardCoordinator) {
            statusMessage = String(localized: "Link copied.")
        }
    }

    func retryUpload() {
        guard let snapshot = pendingUpload, !isUploading, !isExporting else { return }
        guard hosting.profiles.contains(snapshot.profile) else {
            statusMessage = String(localized: "The host configuration changed. Start a new upload to use the new settings.")
            return
        }
        do {
            let credentials = try ScreenshotCredentialStore.load(snapshot.profile.id)
            try credentials.validate(for: snapshot.profile.provider)
            let id = startUploadState(hostName: snapshot.profile.name)
            let clipboardCount = snapshot.copiesLink ? NSPasteboard.general.changeCount : nil
            uploadTask = Task { [weak self] in
                do { try await self?.send(snapshot, credentials: credentials, id: id, clipboardCount: clipboardCount) }
                catch { self?.handleUploadError(error, id: id) }
            }
        } catch { statusMessage = (error as? ScreenshotUploadError)?.localizedDescription ?? ScreenshotUploadError.keychain.localizedDescription }
    }

    private func beginUpload(image: CGImage, edit: ScreenshotEdit, format: ScreenshotFormat, copiesLink: Bool) {
        guard let profile = hosting.selected else {
            statusMessage = String(localized: "Choose an image host in Screenshot settings first.")
            return
        }
        let credentials: ScreenshotHostCredentials
        do {
            try profile.validate()
            credentials = try ScreenshotCredentialStore.load(profile.id)
            try credentials.validate(for: profile.provider)
        } catch {
            statusMessage = (error as? ScreenshotUploadError)?.localizedDescription ?? ScreenshotUploadError.keychain.localizedDescription
            return
        }
        let id = startUploadState(hostName: profile.name)
        pendingUpload = nil
        let clipboardCount = copiesLink ? NSPasteboard.general.changeCount : nil
        let filename = "Screenshot-" + id.uuidString.lowercased() + "." + format.rawValue
        uploadTask = Task { [weak self] in
            do {
                let data = try await ScreenshotRenderer.export(image: image, edit: edit, format: format)
                try Task.checkCancellation()
                guard let self, uploadID == id else { return }
                let snapshot = ScreenshotUploadSnapshot(profile: profile, image: data, format: format,
                    filename: filename, copiesLink: copiesLink)
                pendingUpload = snapshot
                try await send(snapshot, credentials: credentials, id: id, clipboardCount: clipboardCount)
            } catch { self?.handleUploadError(error, id: id) }
        }
    }

    private func startUploadState(hostName: String) -> UUID {
        let id = UUID()
        uploadID = id
        isUploading = true
        uploadProgress = 0
        uploadHostName = hostName
        uploadedURL = nil
        statusMessage = nil
        return id
    }

    private func send(_ snapshot: ScreenshotUploadSnapshot, credentials: ScreenshotHostCredentials, id: UUID, clipboardCount: Int?) async throws {
        let linkFormat = hosting.linkFormat
        let url = try await ScreenshotUploader.upload(profile: snapshot.profile, credentials: credentials,
            image: snapshot.image, format: snapshot.format, filename: snapshot.filename) { [weak self] value in
                Task { @MainActor [weak self] in
                    guard self?.uploadID == id else { return }
                    self?.uploadProgress = value
                }
            }
        try Task.checkCancellation()
        guard uploadID == id else { return }
        uploadedURL = url
        isUploading = false
        uploadID = nil
        uploadTask = nil
        pendingUpload = nil
        statusMessage = String(localized: "Upload complete. The link is ready to copy.")
        if let clipboardCount {
            if ScreenshotClipboard.copyLink(url, format: linkFormat, to: .general,
                    coordinator: clipboardCoordinator, ifUnchangedSince: clipboardCount) {
                statusMessage = String(localized: "Upload complete. Link copied.")
            } else {
                statusMessage = String(localized: "Upload complete. Your clipboard changed, so the link was not copied. Use Copy Link when ready.")
            }
        }
    }

    private func handleUploadError(_ error: Error, id: UUID) {
        guard !Task.isCancelled, uploadID == id else { return }
        isUploading = false
        uploadID = nil
        uploadTask = nil
        statusMessage = (error as? ScreenshotUploadError)?.localizedDescription
            ?? (error as? ScreenshotError)?.localizedDescription ?? ScreenshotUploadError.network.localizedDescription
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func capture(_ mode: ScreenshotMode, purpose: CapturePurpose = .edit) {
        textWindow.close()
        cancelCapture()
        document?.ocr.invalidate()
        cancelUpload()
        uploadedURL = nil
        pendingUpload = nil
        exportTask?.cancel()
        isExporting = false
        window?.orderOut(nil)
        statusMessage = nil
        needsScreenRecordingPermission = false
        let id = UUID()
        let generation = pinGeneration
        captureID = id
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        captureTask = Task { [weak self] in
            do {
                let content = try await ScreenshotCapture.content()
                try Task.checkCancellation()
                guard let self, captureID == id else { return }
                if mode == .screen {
                    guard let screen else { throw ScreenshotError.unavailable }
                    finishCapture(content: content, screen: screen, area: nil, selectedWindow: nil, id: id, purpose: purpose, pinGeneration: generation)
                } else {
                    selection.show(mode: mode, windows: content.windows) { [weak self] screen, area, selectedWindow in
                        self?.finishCapture(content: content, screen: screen, area: area, selectedWindow: selectedWindow, id: id, purpose: purpose, pinGeneration: generation)
                    } cancelled: { [weak self] in
                        self?.cancelCapture()
                        if self?.document != nil { self?.show(on: screen) }
                    }
                }
            } catch {
                guard !Task.isCancelled, self?.captureID == id else { return }
                self?.report(error)
            }
        }
    }

    private func finishCapture(content: SCShareableContent, screen: NSScreen, area: CGRect?, selectedWindow: SCWindow?, id: UUID, purpose: CapturePurpose, pinGeneration generation: Int) {
        selection.finishChoosing()
        captureTask = Task { [weak self] in
            do {
                // Enumerate while the selection panels still exist so the filter can exclude this app.
                let captureContent = area != nil || selectedWindow != nil
                    ? try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) : content
                try Task.checkCancellation()
                guard let self, captureID == id else { return }
                selection.close()
                let image = try await ScreenshotCapture.image(content: captureContent, screen: screen, area: area, window: selectedWindow)
                try Task.checkCancellation()
                guard captureID == id, isEnabled else { return }
                switch purpose {
                case .edit:
                    self.document = ScreenshotDocument(image: image)
                    show(on: screen)
                case .pin:
                    if document != nil { show(on: screen) }
                    if pinGeneration == generation { try addPin(image) }
                case .text:
                    if document != nil { show(on: screen) }
                    textWindow.show(image: image) { [weak self] in self?.copyText($0) }
                }
            } catch {
                guard !Task.isCancelled, self?.captureID == id else { return }
                self?.selection.close()
                self?.report(error)
            }
        }
    }

    private func report(_ error: Error) {
        if case ScreenshotError.permission = error { needsScreenRecordingPermission = true }
        statusMessage = (error as? ScreenshotError)?.localizedDescription ?? ScreenshotError.captureFailed.localizedDescription
        show(on: NSScreen.main)
    }

    private func show(on screen: NSScreen?) {
        if window == nil {
            let panel = ScreenshotWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = String(localized: "Screenshot")
            panel.minSize = CGSize(width: 640, height: 400)
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.didClose = { [weak self] in self?.closeEditor() }
            panel.contentView = NSHostingView(rootView: ScreenshotEditorView(plugin: self))
            window = panel
        }
        if let screen {
            let frame = screen.visibleFrame
            if let window {
                let size = CGSize(width: min(window.frame.width, frame.width), height: min(window.frame.height, frame.height))
                window.setFrame(CGRect(origin: window.frame.origin, size: size), display: false)
            }
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

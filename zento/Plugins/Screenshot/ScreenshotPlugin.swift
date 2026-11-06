import AppKit
import Observation
import SwiftUI
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class ScreenshotPlugin {
    private enum CapturePurpose { case edit, text, pin, scroll }
    private var scrollSession: ScreenshotScrollSession?
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
    private let preview = ScreenshotPreviewController()
    private var captureTask: Task<Void, Never>?
    private var captureID: UUID?
    @ObservationIgnored private var window: ScreenshotWindow?
    private(set) var isEnabled: Bool
    private(set) var statusMessage: String?
    private(set) var needsScreenRecordingPermission = false
    private(set) var isScreenRecordingAuthorized = false
    private(set) var document: ScreenshotDocument?
    private(set) var isExporting = false {
        didSet { window?.toolbar?.validateVisibleItems() }
    }
    var format: ScreenshotFormat {
        didSet { defaults.set(format.rawValue, forKey: "plugin.screenshot.format") }
    }
    var opensEditorAfterCapture: Bool {
        didSet { defaults.set(opensEditorAfterCapture, forKey: "plugin.screenshot.opens-editor") }
    }
    var automaticallyCopy: Bool {
        didSet { defaults.set(automaticallyCopy, forKey: "plugin.screenshot.auto-copy") }
    }
    var automaticallySave: Bool {
        didSet { defaults.set(automaticallySave, forKey: "plugin.screenshot.auto-save") }
    }
    private(set) var saveDirectory: URL?
    var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: "plugin.screenshot.jpeg-quality") }
    }
    private var exportTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private lazy var upload = ScreenshotUploadSession(
        hosting: hosting, coordinator: clipboardCoordinator,
        status: { [weak self] in self?.statusMessage = $0 },
        changed: { [weak self] in self?.window?.toolbar?.validateVisibleItems() },
        completed: { [weak self] in self?.closeEditor() }
    )
    var canRetryUpload: Bool { upload.canRetryUpload && !isExporting }
    var isUploading: Bool { upload.isUploading }
    var uploadProgress: Double { upload.uploadProgress }
    var uploadedURL: URL? { upload.uploadedURL }
    var uploadHostName: String { upload.uploadHostName }

    init(defaults: UserDefaults = .standard, clipboardCoordinator: ClipboardAccessCoordinator) {
        self.defaults = defaults
        hosting = ScreenshotHostingSettings(defaults: defaults)
        format = ScreenshotFormat(rawValue: defaults.string(forKey: "plugin.screenshot.format") ?? "") ?? .png
        opensEditorAfterCapture = defaults.bool(forKey: "plugin.screenshot.opens-editor")
        automaticallyCopy = defaults.bool(forKey: "plugin.screenshot.auto-copy")
        automaticallySave = defaults.bool(forKey: "plugin.screenshot.auto-save")
        saveDirectory = defaults.url(forKey: "plugin.screenshot.save-directory")
        jpegQuality = defaults.object(forKey: "plugin.screenshot.jpeg-quality") as? Double ?? 0.9
        self.clipboardCoordinator = clipboardCoordinator
        isEnabled = defaults.bool(forKey: "plugin.screenshot.enabled")
    }

    func register(in registry: CommandRegistry, openSettings: @escaping @MainActor () throws -> Void) throws {
        for mode in ScreenshotMode.allCases {
            try registry.register(CommandDescriptor(systemImage: "camera.viewfinder", id: mode.commandID, title: mode.title,
                category: String(localized: "Screenshot"), subtitle: nil, keywords: ["screenshot", "capture", "截图", "截屏"] + (mode == .scrolling ? ["scroll", "滚动截图"] : []))) { [weak self] _ in
                guard let self else { return }
                guard isEnabled else { try openSettings(); return }
                capture(mode)
            }
        }
        try registry.register(CommandDescriptor(systemImage: "camera.viewfinder", id: Self.textCommandID, title: String(localized: "Capture Text"),
            category: String(localized: "Screenshot"), subtitle: nil, keywords: ["ocr", "text", "识别文字", "截图文字"])) { [weak self] _ in
            guard let self else { return }
            guard isEnabled else { try openSettings(); return }
            capture(.area, purpose: .text)
        }
        for command in PinCommand.allCases {
            try registry.register(CommandDescriptor(systemImage: "camera.viewfinder", id: command.id, title: command.title,
                category: String(localized: "Screenshot"), subtitle: nil, keywords: ["pin", "image", "贴图", "悬浮", "图片"])) { [weak self] _ in
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
        preview.close()
        feedbackTask?.cancel()
        feedbackTask = nil
        cancelCapture()
        document?.ocr.invalidate()
        upload.discardUpload()
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        cancelExport()
        document = nil
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
    }

    func cancelCapture() {
        captureID = nil
        scrollSession?.close()
        scrollSession = nil
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

    func pinImage(closesEditor: Bool = false) {
        guard let document, !isExporting, !isUploading else { return }
        isExporting = true
        let edit = document.edit
        let generation = pinGeneration
        exportTask = Task { [weak self] in
            do {
                let image = try await ScreenshotRenderer.flattened(image: document.image, edit: edit)
                guard !Task.isCancelled, let self, self.document === document else { return }
                if pinGeneration == generation {
                    try addPin(image)
                    if closesEditor { self.closeEditor() }
                }
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

    func copyImage(closesEditor: Bool = false) {
        export(format: .png) { [weak self] data in
            let board = NSPasteboard.general
            board.prepareForNewContents(with: .currentHostOnly)
            guard board.setData(data, forType: .png) else { throw ScreenshotError.exportFailed }
            if closesEditor { self?.closeEditor() }
            else { self?.showExportFeedback(String(localized: "Image copied.")) }
        }
    }

    func saveImage(closesEditor: Bool = false) {
        guard let document, !isExporting, !isUploading else { return }
        let selectedFormat = format
        let panel = NSSavePanel()
        panel.directoryURL = saveDirectory
        panel.allowedContentTypes = [selectedFormat.type]
        panel.nameFieldStringValue = "Screenshot-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))-\(UUID().uuidString.prefix(8)).\(format.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url, self.document === document else { return }
        export(format: selectedFormat) { [weak self] data in
            try data.write(to: url, options: .atomic)
            if closesEditor { self?.closeEditor() }
            else { self?.showExportFeedback(String(localized: "Image saved.")) }
        }
    }

    private func showExportFeedback(_ message: String) {
        feedbackTask?.cancel()
        statusMessage = message
        let document = document
        feedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            guard let self, self.document === document, self.statusMessage == message else { return }
            self.statusMessage = nil
            self.feedbackTask = nil
        }
    }

    private func export(format: ScreenshotFormat, completed: @escaping @MainActor (Data) throws -> Void) {
        guard let document, !isExporting, !isUploading else { return }
        isExporting = true
        statusMessage = nil
        let edit = document.edit
        let quality = jpegQuality
        exportTask = Task { [weak self] in
            do {
                let data = try await ScreenshotRenderer.export(image: document.image, edit: edit, format: format, quality: quality)
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
        if hosting.automaticallyUpload {
            guard let document, !isUploading, !isExporting else { return }
            upload.beginUpload(quality: jpegQuality, image: document.image, edit: document.edit, format: format, copiesLink: true, closesEditor: true)
        } else { copyImage(closesEditor: true) }
    }

    func uploadImage(closesEditor: Bool = false) {
        guard let document, !isUploading, !isExporting else { return }
        upload.beginUpload(quality: jpegQuality, image: document.image, edit: document.edit, format: format, copiesLink: true, closesEditor: closesEditor)
    }

    func uploadTestImage() {
        guard !isUploading, !isExporting else { return }
        guard let context = CGContext(data: nil, width: 160, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
        guard let image = context.makeImage() else { return }
        upload.beginUpload(quality: jpegQuality, image: image, edit: ScreenshotEdit(crop: CGRect(x: 0, y: 0, width: 160, height: 80)), format: .png, copiesLink: false)
    }

    func cancelUpload() { upload.cancelUpload() }
    func copyUploadedLink() { upload.copyUploadedLink() }
    func retryUpload() {
        guard !isExporting else { return }
        upload.retryUpload()
    }

    func refreshScreenRecordingPermission() {
        isScreenRecordingAuthorized = CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
        refreshScreenRecordingPermission()
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func capture(_ mode: ScreenshotMode, purpose: CapturePurpose = .edit) {
        cancelCapture()
        upload.discardUpload()
        cancelExport()
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
                        self?.finishCapture(content: content, screen: screen, area: area, selectedWindow: selectedWindow, id: id, purpose: mode == .scrolling ? .scroll : purpose, pinGeneration: generation)
                    } cancelled: { [weak self] in
                        self?.cancelCapture()
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
                try Task.checkCancellation()
                guard let self, captureID == id else { return }
                if purpose == .scroll, let area {
                    let session = ScreenshotScrollSession(content: content, screen: screen, area: area) { [weak self] image in
                        guard let self, captureID == id, isEnabled else { return }
                        selection.close()
                        scrollSession = nil
                        captureID = nil
                        acceptCapture(image, on: screen)
                    } cancelled: { [weak self] in
                        guard let self, captureID == id else { return }
                        cancelCapture()
                    }
                    scrollSession = session
                    session.start()
                    return
                }
                let image = try await ScreenshotCapture.image(content: content, screen: screen, area: area, window: selectedWindow)
                try Task.checkCancellation()
                guard captureID == id, isEnabled else { return }
                selection.close()
                switch purpose {
                case .edit, .scroll:
                    acceptCapture(image, on: screen)
                case .pin:
                    if pinGeneration == generation { try addPin(image) }
                case .text:
                    textWindow.show(image: image) { [weak self] in self?.copyText($0) }
                }
            } catch {
                guard !Task.isCancelled, self?.captureID == id else { return }
                self?.selection.close()
                self?.report(error)
            }
        }
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveDirectory = url
        defaults.set(url, forKey: "plugin.screenshot.save-directory")
    }

    func editPreview() { show(on: preview.screen) }
    func recognizePreview() {
        guard let document else { return }
        textWindow.show(image: document.image) { [weak self] in self?.copyText($0) }
        closeEditor()
    }
    func dismissPreview() { closeEditor() }

    private func acceptCapture(_ image: CGImage, on screen: NSScreen) {
        let document = ScreenshotDocument(image: image)
        self.document = document
        statusMessage = nil
        if opensEditorAfterCapture { show(on: screen) }
        else { preview.show(plugin: self, image: image, on: screen) }
        let edit = document.edit
        let copy = automaticallyCopy
        let save = automaticallySave
        guard copy || save else { return }
        let directory = saveDirectory
        let format = format
        let quality = jpegQuality
        let clipboardCount = NSPasteboard.general.changeCount
        isExporting = true
        exportTask = Task { [weak self] in
            guard let self else { return }
            var failures: [String] = []
            if copy {
                do {
                    let data = try await ScreenshotRenderer.encode(image, format: .png)
                    try Task.checkCancellation()
                    guard self.document === document else { return }
                    let board = NSPasteboard.general
                    if board.changeCount == clipboardCount {
                        board.prepareForNewContents(with: .currentHostOnly)
                        let copied = board.setData(data, forType: .png)
                        if !copied { throw ScreenshotError.exportFailed }
                    } else {
                        failures.append(String(localized: "Your clipboard changed. Use Copy Image when ready."))
                    }
                } catch {
                    guard !Task.isCancelled, self.document === document else { return }
                    failures.append(String(localized: "Automatic copying failed. Try Copy Image again."))
                }
            }
            if save {
                do {
                    guard let directory else { throw ScreenshotError.exportFailed }
                    let data = try await ScreenshotRenderer.export(image: image, edit: edit, format: format, quality: quality)
                    try Task.checkCancellation()
                    guard self.document === document else { return }
                    _ = try await ScreenshotAutomaticSave.write(data, format: format, directory: directory)
                } catch {
                    guard !Task.isCancelled, self.document === document else { return }
                    failures.append(String(localized: "Automatic saving failed. Choose a writable folder in Screenshot settings."))
                }
            }
            guard !Task.isCancelled, self.document === document else { return }
            isExporting = false
            exportTask = nil
            if !failures.isEmpty { statusMessage = failures.joined(separator: "\n") }
        }
    }

    private func report(_ error: Error) {
        if case ScreenshotError.permission = error { needsScreenRecordingPermission = true }
        statusMessage = (error as? ScreenshotError)?.localizedDescription ?? ScreenshotError.captureFailed.localizedDescription
        show(on: NSScreen.main)
    }

    private func show(on screen: NSScreen?) {
        preview.close()
        if window == nil {
            let panel = ScreenshotWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 240),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = String(localized: "Screenshot")
            panel.minSize = CGSize(width: 480, height: 220)
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            let editorToolbar = ScreenshotEditorToolbar(plugin: self)
            panel.editorToolbar = editorToolbar
            panel.toolbar = editorToolbar.makeToolbar()
            panel.toolbarStyle = .unifiedCompact
            panel.didClose = { [weak self] in self?.closeEditor() }
            panel.contentView = NSHostingView(rootView: ScreenshotEditorView(plugin: self))
            window = panel
        }
        if let screen = screen ?? NSScreen.main, let window {
            let frame = screen.visibleFrame
            if let document, window.fittedDocument !== document {
                let chrome = window.frame.height - window.contentLayoutRect.height
                let available = CGSize(width: frame.width * 0.85, height: frame.height * 0.85)
                let zoom = min(1 / screen.backingScaleFactor,
                               (available.width - 24) / document.edit.crop.width,
                               (available.height - chrome - 52) / document.edit.crop.height)
                document.zoom = zoom
                let content = CGSize(width: max(480, document.edit.crop.width * zoom + 24),
                                     height: max(180, document.edit.crop.height * zoom + 52))
                window.setFrame(CGRect(origin: window.frame.origin,
                                       size: CGSize(width: content.width, height: content.height + chrome)), display: false)
                window.fittedDocument = document
            }
            window.setFrameOrigin(CGPoint(x: frame.midX - window.frame.width / 2,
                                          y: frame.midY - window.frame.height / 2))
        }
        if let window { WindowPresentation.present(window) }
    }
}

final class ScreenshotWindow: NSWindow {
    weak var fittedDocument: ScreenshotDocument?
    var editorToolbar: ScreenshotEditorToolbar?
    var didClose: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !(firstResponder is NSTextView), editorToolbar?.handleKeyEquivalent(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func close() { super.close(); didClose?() }
}

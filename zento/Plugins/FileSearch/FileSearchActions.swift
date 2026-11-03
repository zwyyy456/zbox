import AppKit
import QuickLookUI

@MainActor final class FileSearchActions {
    enum Action { case open, reveal, copyFile, copyPath, preview }
    private let coordinator: ClipboardAccessCoordinator
    private var previewPanel: FileSearchPreviewPanel?
    private var previewView: QLPreviewView?
    var dismissSession: (() -> Void)?

    init(coordinator: ClipboardAccessCoordinator) { self.coordinator = coordinator }

    func perform(_ action: Action, url: URL, parent: NSWindow?) throws {
        guard (try? url.checkResourceIsReachable()) == true else { throw FileSearchError.missingFile }
        switch action {
        case .open:
            guard NSWorkspace.shared.open(url) else { throw FileSearchError.actionFailed }
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copyFile, .copyPath:
            let board = NSPasteboard.general
            board.prepareForNewContents(with: .currentHostOnly)
            defer { coordinator.didWrite(changeCount: board.changeCount) }
            let success = action == .copyFile ? board.writeObjects([url as NSURL]) : board.setString(url.path, forType: .string)
            guard success else { throw FileSearchError.actionFailed }
        case .preview:
            closePreview()
            let panel = FileSearchPreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            guard let view = QLPreviewView(frame: panel.contentView?.bounds ?? .zero, style: .normal) else {
                throw FileSearchError.actionFailed
            }
            panel.dismissAfterFocusLoss = { [weak self] in self?.dismissSession?() }
            panel.onDismiss = { [weak self] in self?.closePreview() }
            panel.title = url.lastPathComponent
            panel.contentView = view
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.center()
            previewPanel = panel
            previewView = view
            view.previewItem = url as NSURL
            parent?.addChildWindow(panel, ordered: .above)
            panel.presentTransient()
        }
    }

    @discardableResult func closePreview() -> Bool {
        guard let previewPanel else { return false }
        let parent = previewPanel.parent
        let restoreFocus = previewPanel.isKeyWindow
        parent?.removeChildWindow(previewPanel)
        previewView?.previewItem = nil
        previewView?.close()
        previewPanel.orderOut(nil)
        if restoreFocus { parent?.makeKey() }
        self.previewPanel = nil
        previewView = nil
        return true
    }
}

@MainActor private final class FileSearchPreviewPanel: TransientPanel {
    var onDismiss: (() -> Void)?
    override func close() { onDismiss?(); super.close() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

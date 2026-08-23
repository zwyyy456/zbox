import AppKit
import SwiftUI

@MainActor
final class SearchPanelController: NSObject, NSWindowDelegate {
    private weak var environment: AppEnvironment?
    private let panel: SearchPanel

    var isVisible: Bool {
        panel.isVisible
    }

    init(environment: AppEnvironment) {
        self.environment = environment

        let content = RootSearchView(environment: environment)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 420)

        panel = SearchPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.contentView = hostingView
        panel.onReturn = { [weak self] in
            self?.executeSelectedCommand()
        }
        panel.onMoveSelection = { [weak self] offset in
            self?.moveSelection(by: offset)
        }
        panel.onEscape = { [weak environment] in
            environment?.hideRootSearch()
        }
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
    }

    func show() {
        positionOnCurrentScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        if let searchField = firstTextField(in: panel.contentView) {
            panel.makeFirstResponder(searchField)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func positionOnCurrentScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let panelSize = panel.frame.size
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2 + visibleFrame.height * 0.12
        )
        panel.setFrameOrigin(origin)
    }

    private func executeSelectedCommand() {
        guard let environment else { return }
        synchronizeSearchQuery(with: environment)
        environment.executeSelectedCommand()
    }

    private func moveSelection(by offset: Int) {
        guard let environment else { return }
        synchronizeSearchQuery(with: environment)
        environment.moveSelection(by: offset)
    }

    private func synchronizeSearchQuery(with environment: AppEnvironment) {
        guard let searchField = firstTextField(in: panel.contentView),
              searchField.stringValue != environment.searchQuery else {
            return
        }
        environment.searchQuery = searchField.stringValue
    }

    private func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }
        for subview in view.subviews {
            if let textField = firstTextField(in: subview) {
                return textField
            }
        }
        return nil
    }
}

@MainActor
private final class SearchPanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let action = SearchKeyboardMapper.action(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
           ) {
            switch action {
            case .moveSelection(let offset):
                onMoveSelection?(offset)
            case .execute:
                onReturn?()
            case .dismiss:
                onEscape?()
            }
            return
        }
        super.sendEvent(event)
    }
}

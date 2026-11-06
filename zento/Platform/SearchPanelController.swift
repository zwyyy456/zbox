import AppKit
import SwiftUI

@MainActor
final class SearchPanelController: NSObject {
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
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = CommandPanelAppearance.cornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        panel = SearchPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
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
            guard let environment else { return }
            if environment.rootSearch.isShowingRootSearchActions {
                environment.rootSearch.isShowingRootSearchActions = false
            } else {
                environment.hideRootSearch()
            }
        }
        panel.onToggleActions = { [weak self] in
            self?.toggleActions()
        }
        panel.dismissAfterFocusLoss = { [weak environment] in environment?.hideRootSearch() }
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        // The content fills with windowBackgroundColor; keep only the rounded corners transparent.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
    }

    func show() {
        positionOnCurrentScreen()
        panel.presentTransient()
    }

    func hide() {
        panel.orderOut(nil)
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
        if environment.rootSearch.isShowingRootSearchActions {
            environment.performSelectedRootSearchAction()
        } else {
            environment.executeSelectedCommand()
        }
    }

    private func toggleActions() {
        guard let environment else { return }
        synchronizeSearchQuery(with: environment)
        guard let selected = environment.rootSearch.selectedSearchMatch,
              !environment.rootSearchActions(for: selected.id).isEmpty else {
            environment.rootSearch.isShowingRootSearchActions = false
            NSSound.beep()
            return
        }
        environment.rootSearch.isShowingRootSearchActions.toggle()
    }

    private func moveSelection(by offset: Int) {
        guard let environment else { return }
        synchronizeSearchQuery(with: environment)
        environment.moveSelection(by: offset)
    }

    private func synchronizeSearchQuery(with environment: AppEnvironment) {
        guard let searchField = firstTextField(in: panel.contentView),
              searchField.stringValue != environment.rootSearch.searchQuery else {
            return
        }
        environment.rootSearch.searchQuery = searchField.stringValue
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
final class SearchPanel: TransientPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onToggleActions: (() -> Void)?


    override func sendEvent(_ event: NSEvent) {
        if !handleCommandKey(event) { super.sendEvent(event) }
    }

    /// Input methods own command keys until their marked text is committed.
    func handleCommandKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              (firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        if SearchKeyboardMapper.isActionsShortcut(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) {
            onToggleActions?()
            return true
        }
        guard let action = SearchKeyboardMapper.action(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) else { return false }
        switch action {
        case .moveSelection(let offset): onMoveSelection?(offset)
        case .execute: onReturn?()
        case .dismiss: onEscape?()
        }
        return true
    }
}

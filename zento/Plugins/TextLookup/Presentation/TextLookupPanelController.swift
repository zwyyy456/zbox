import AppKit
import SwiftUI
import LookupPresentation

@MainActor
final class TextLookupPanelController {
    private let model: TextLookupSessionModel
    private let settings: TextLookupSettingsStore
    private let onDismiss: () -> Void
    private lazy var window: LookupWindowController = {
        let controller = LookupWindowController(state: model.windowState) {
            TextLookupPanelView(model: model, settings: settings, onClose: { [weak self] in self?.hide() })
        }
        controller.onDismiss = { [onDismiss] _ in onDismiss() }
        return controller
    }()
    init(model: TextLookupSessionModel, settings: TextLookupSettingsStore,
         onDismiss: @escaping () -> Void) {
        self.model = model; self.settings = settings; self.onDismiss = onDismiss
    }
    func contains(_ window: NSWindow?) -> Bool { self.window.contains(window) }
    func show(anchor: CGRect?) throws { try window.present(anchor: anchor) }
    func dismissForOutsideClick() { window.dismissForOutsideClick() }
    func hide(notify: Bool = true) {
        window.dismiss(notify: false)
        if notify { onDismiss() }
    }
}

import SwiftUI

/// Plain text only: code must not be changed by smart quotes or substitutions.
struct DeveloperTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var label: String
    var selectionRequest: (id: UUID, offset: Int)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let editor = scrollView.documentView as! NSTextView
        editor.isRichText = false
        editor.isEditable = isEditable
        editor.isSelectable = true
        editor.allowsUndo = isEditable
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.setAccessibilityLabel(label)
        editor.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let editor = view.documentView as! NSTextView
        if let request = selectionRequest, request.id != context.coordinator.selectionID {
            context.coordinator.selectionID = request.id
            let offset = min(request.offset, editor.string.utf16.count)
            let range = NSRange(location: offset, length: 0)
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
            editor.window?.makeFirstResponder(editor)
        }
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var selectionID: UUID?
        var parent: DeveloperTextEditor
        init(_ parent: DeveloperTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

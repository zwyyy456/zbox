import AppKit

@MainActor
final class ScreenshotEditorToolbar: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    private let plugin: ScreenshotPlugin
    private let tools = ScreenshotTool.allCases
    private let symbols = ["crop", "arrow.up.right", "rectangle", "t.square", "square.grid.3x3.fill", "rectangle.fill"]

    init(plugin: ScreenshotPlugin) { self.plugin = plugin }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "ScreenshotEditor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("copy"), .init("save"), .init("pin"), .space, .init("tools"), .init("undo"), .init("redo"),
         .flexibleSpace, .init("ocr"), .init("more"), .init("done")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id.rawValue == "tools" {
            let group = NSToolbarItemGroup(itemIdentifier: id,
                images: symbols.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil)! },
                selectionMode: .selectOne, labels: tools.map(\.title), target: self, action: #selector(selectTool(_:)))
            group.label = String(localized: "Tool")
            group.selectedIndex = tools.firstIndex(of: plugin.document?.tool ?? .arrow)!
            for (item, tool) in zip(group.subitems, tools) { item.toolTip = tool.title }
            return group
        }
        if id.rawValue == "more" {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = String(localized: "Image Actions")
            item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: item.label)
            let menu = NSMenu()
            menu.addItem(menuItem(String(localized: "Upload"), #selector(upload)))
            menu.addItem(.separator())
            let format = NSMenuItem(title: String(localized: "Format"), action: nil, keyEquivalent: "")
            let formats = NSMenu()
            for (index, value) in ScreenshotFormat.allCases.enumerated() {
                let entry = menuItem(value.title, #selector(selectFormat(_:)))
                entry.tag = index
                formats.addItem(entry)
            }
            format.submenu = formats
            menu.addItem(format)
            item.menu = menu
            return item
        }
        let item = NSToolbarItem(itemIdentifier: id)
        let values: (String, String, Selector)
        switch id.rawValue {
        case "copy": values = (String(localized: "Copy Image"), "doc.on.doc", #selector(copyImage))
        case "save": values = (String(localized: "Save…"), "square.and.arrow.down", #selector(save))
        case "pin": values = (String(localized: "Pin Image"), "pin", #selector(pin))
        case "undo": values = (String(localized: "Undo"), "arrow.uturn.backward", #selector(undo))
        case "redo": values = (String(localized: "Redo"), "arrow.uturn.forward", #selector(redo))
        case "ocr": values = (String(localized: "Recognize Text"), "text.viewfinder", #selector(ocr))
        case "done": values = (plugin.completionTitle, "checkmark.circle", #selector(done))
        default: return nil
        }
        item.label = values.0
        item.toolTip = values.0
        item.image = NSImage(systemSymbolName: values.1, accessibilityDescription: values.0)
        item.target = self
        item.action = values.2
        return item
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        let available = plugin.document != nil && !plugin.isExporting && !plugin.isUploading
        switch item.itemIdentifier.rawValue {
        case "undo": return available && plugin.document?.canUndo == true
        case "redo": return available && plugin.document?.canRedo == true
        case "tools":
            (item as? NSToolbarItemGroup)?.selectedIndex = tools.firstIndex(of: plugin.document?.tool ?? .arrow)!
            return available && plugin.document?.showsText == false
        case "ocr":
            item.label = plugin.document?.showsText == true ? String(localized: "Image") : String(localized: "Recognize Text")
            item.toolTip = item.label
            item.image = NSImage(systemSymbolName: plugin.document?.showsText == true ? "photo" : "text.viewfinder", accessibilityDescription: item.label)
        case "done": item.label = plugin.completionTitle; item.toolTip = item.label
        default: break
        }
        return available
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(selectFormat(_:)) {
            item.state = ScreenshotFormat.allCases[item.tag] == plugin.format ? .on : .off
        }
        return plugin.document != nil && !plugin.isExporting && !plugin.isUploading
    }

    @objc private func selectTool(_ sender: NSToolbarItemGroup) { finishText(); plugin.document?.tool = tools[sender.selectedIndex] }

    private func finishText() { NSApp.keyWindow?.makeFirstResponder(nil) }

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command || modifiers == [.command, .shift],
              plugin.document != nil, !plugin.isExporting, !plugin.isUploading else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c" where modifiers == .command: copyImage()
        case "s" where modifiers == .command: save()
        case "z": modifiers.contains(.shift) ? redo() : undo()
        case "\r" where modifiers == .command: done()
        default: return false
        }
        return true
    }
    @objc private func selectFormat(_ sender: NSMenuItem) { plugin.format = ScreenshotFormat.allCases[sender.tag] }
    @objc private func copyImage() { finishText(); plugin.copyImage() }
    @objc private func save() { finishText(); plugin.saveImage() }
    @objc private func upload() { finishText(); plugin.uploadImage() }
    @objc private func pin() { finishText(); plugin.pinImage() }
    @objc private func undo() { finishText(); plugin.document?.undo() }
    @objc private func redo() { finishText(); plugin.document?.redo() }
    @objc private func done() { finishText(); plugin.finishEditing() }
    @objc private func ocr() {
        finishText()
        guard let document = plugin.document else { return }
        document.showsText.toggle()
        if document.showsText { document.ocr.run(image: document.image, edit: document.edit) }
    }
}

import SwiftUI

struct FileSearchView: View {
    @Bindable var plugin: FileSearchPlugin
    private enum Focus { case search, results }
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search file names — ext:pdf, type:folder, path:project", text: $plugin.query)
                .textFieldStyle(.roundedBorder).focused($focus, equals: .search)
            HStack {
                Picker("Search Folder", selection: $plugin.scope) {
                    Text("All Search Folders").tag("")
                    ForEach(plugin.settings.roots) { Text($0.url.lastPathComponent).tag($0.id.uuidString) }
                }
                Picker("Type", selection: $plugin.typeFilter) {
                    Text("All Types").tag("")
                    Text("Files").tag("file")
                    Text("Folders").tag("folder")
                }.frame(maxWidth: 160)
                TextField("Extension", text: $plugin.extensionFilter).frame(width: 85)
                Picker("Sort", selection: $plugin.sort) {
                    Text("Relevance").tag(FileSearchSort.relevance)
                    Text("Name").tag(FileSearchSort.name)
                    Text("Modified").tag(FileSearchSort.modified)
                }.frame(maxWidth: 170)
            }
            List(plugin.page.files, selection: $plugin.selectedID) { file in
                HStack(spacing: 12) {
                    Image(systemName: file.isDirectory ? "folder" : "doc").frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.name).lineLimit(1)
                        if let root = plugin.settings.roots.first(where: { $0.id == file.rootID }) {
                            Text(root.url.appending(path: file.path).deletingLastPathComponent().path)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(file.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .font(.caption).frame(width: 70, alignment: .trailing)
                    Text(file.modified, format: .dateTime.year().month().day())
                        .font(.caption).frame(width: 100, alignment: .trailing)
                }.tag(file.id)
                .contextMenu {
                    Button("Open") { plugin.selectedID = file.id; plugin.perform(.open) }
                    Button("Show in Finder") { plugin.selectedID = file.id; plugin.perform(.reveal) }
                    Button("Copy File") { plugin.selectedID = file.id; plugin.perform(.copyFile) }
                    Button("Copy Path") { plugin.selectedID = file.id; plugin.perform(.copyPath) }
                    Button("Quick Look") { plugin.selectedID = file.id; plugin.perform(.preview) }
                }
            }
            .focused($focus, equals: .results)
            HStack {
                if plugin.isSearching { ProgressView().controlSize(.small) }
                Text(plugin.page.hasMore ? String(localized: "Showing the best 200 matches. Narrow your search for more.") : String(localized: "\(plugin.page.files.count) matches"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quick Look") { plugin.perform(.preview) }.disabled(plugin.selectedFile == nil)
                Menu("Actions") {
                    Button("Open") { plugin.perform(.open) }
                    Button("Show in Finder") { plugin.perform(.reveal) }
                    Button("Copy File") { plugin.perform(.copyFile) }
                    Button("Copy Path") { plugin.perform(.copyPath) }
                }.disabled(plugin.selectedFile == nil)
            }
            Text("Opening or previewing cloud files may download them.").font(.caption).foregroundStyle(.secondary)
            if plugin.query.isEmpty && plugin.typeFilter.isEmpty && plugin.extensionFilter.isEmpty {
                Text("Enter a file name or choose a filter. Add search folders in Settings.").font(.caption)
            }
            if let error = plugin.searchError { SettingsErrorView(message: error) }
            if !plugin.rootStatus.isEmpty {
                Text(plugin.rootStatus.values.sorted().joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(16)
        .onAppear { focus = .search }
        .onChange(of: focus) { plugin.resultsFocused = focus == .results }
    }
}

@MainActor final class FileSearchPanel: NSPanel {
    var navigate: ((Int) -> Void)?
    var dismiss: (() -> Void)?
    var performAction: ((FileSearchActions.Action) -> Void)?
    var canPreview: (() -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func close() { dismiss?(); super.close() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true {
            let modifiers = event.modifierFlags.intersection([.command, .control, .shift, .option])
            if [36, 76].contains(event.keyCode), modifiers == .command { performAction?(.reveal); return }
            if event.keyCode == 8, modifiers == [.command, .shift] { performAction?(.copyPath); return }
            if event.keyCode == 8, modifiers == .command, (firstResponder as? NSTextView)?.selectedRange().length ?? 0 == 0 {
                performAction?(.copyFile); return
            }
            if event.keyCode == 49, modifiers.isEmpty, canPreview?() == true { performAction?(.preview); return }
        }
        if event.type == .keyDown, (firstResponder as? NSTextView)?.hasMarkedText() != true,
           let action = SearchKeyboardMapper.action(keyCode: event.keyCode, charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifierFlags: event.modifierFlags) {
            switch action {
            case .moveSelection(let offset): navigate?(offset); return
            case .dismiss: dismiss?(); return
            case .execute: performAction?(.open); return
            }
        }
        super.sendEvent(event)
    }
}

struct FinderSelectionView: View {
    let plugin: FileSearchPlugin
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Finder Selection").font(.headline)
            if let url = plugin.finderSelection {
                Text(url.lastPathComponent).font(.title2).lineLimit(2)
                Text(url.path).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button("Open") { plugin.perform(.open) }
                Button("Show in Finder") { plugin.perform(.reveal) }
                Button("Quick Look") { plugin.perform(.preview) }
            }
            HStack {
                Button("Copy File") { plugin.perform(.copyFile) }
                Button("Copy Path") { plugin.perform(.copyPath) }
            }
            Text("This selection is temporary and is not added to the file index.").foregroundStyle(.secondary)
            Text("Opening or previewing cloud files may download them.").font(.caption).foregroundStyle(.secondary)
            if let error = plugin.searchError { SettingsErrorView(message: error) }
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

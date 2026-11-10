import SwiftUI

struct FileSearchView: View {
    @Bindable var plugin: FileSearchPlugin
    @State private var searchFocused = false
    @FocusState private var resultsFocused: Bool

    private let horizontalInset: CGFloat = 16

    var body: some View {
        let hasSelection = plugin.selectedFile != nil
        let indexStatus = indexSummary
        VStack(spacing: 0) {
            searchControls
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
                        .font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                    Text(file.modified, format: .dateTime.year().month().day())
                        .font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
                }.tag(file.id)
                .contextMenu {
                    Button("Open") { plugin.selectedID = file.id; plugin.perform(.open) }
                    Button("Show in Finder") { plugin.selectedID = file.id; plugin.perform(.reveal) }
                    Button("Copy File") { plugin.selectedID = file.id; plugin.perform(.copyFile) }
                    Button("Copy Path") { plugin.selectedID = file.id; plugin.perform(.copyPath) }
                    Button("Quick Look") { plugin.selectedID = file.id; plugin.perform(.preview) }
                }
            }
            .focused($resultsFocused)
            .overlay {
                if !hasSearchInput {
                    ContentUnavailableView("Search Files", systemImage: "doc.text.magnifyingglass",
                                           description: plugin.settings.roots.isEmpty
                                               ? Text("Add search folders in Settings.")
                                               : Text("Enter a file name or choose a filter."))
                } else if !plugin.isSearching, plugin.searchError == nil, plugin.page.files.isEmpty,
                          !indexStatus.isIndexing {
                    ContentUnavailableView.search(text: plugin.query)
                }
            }
            if hasSelection || plugin.isSearching || plugin.searchError != nil
                || indexStatus.isIndexing || indexStatus.hasIssue {
                footer(hasSelection: hasSelection, indexStatus: indexStatus)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: resultsFocused) { plugin.resultsFocused = resultsFocused }
    }

    private var searchControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                NativeSearchField(title: String(localized: "Search File Names"), text: $plugin.query,
                                  isFocused: $searchFocused)
                    .help("Search file names — ext:pdf, type:folder, path:project")
                HStack(spacing: 10) {
                    TextField("Extension", text: $plugin.extensionFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    filterMenu
                }
                .controlSize(.small)
            }
            if hasActiveFilters {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(filterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Clear Filters") {
                        plugin.scope = ""
                        plugin.typeFilter = ""
                        plugin.extensionFilter = ""
                        plugin.sort = .relevance
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 12)
    }

    private func footer(hasSelection: Bool, indexStatus: (isIndexing: Bool, hasIssue: Bool)) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let error = plugin.searchError {
                    SettingsErrorView(message: error)
                } else if plugin.isSearching {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                        Text("Searching…")
                    }
                } else if !plugin.page.files.isEmpty {
                    Text(plugin.page.hasMore
                         ? String(localized: "Showing the best 200 matches. Narrow your search for more.")
                         : String(localized: "\(plugin.page.files.count) matches"))
                }
                if indexStatus.isIndexing {
                    Text("Indexing search folders…")
                }
                if indexStatus.hasIssue {
                    Label("Search results may be incomplete. Check search folders in Settings.",
                          systemImage: "exclamationmark.triangle")
                }
                if isSelectionInCloud {
                    Text("Opening or previewing cloud files may download them.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasSelection {
                HStack(spacing: 10) {
                    Button("Quick Look") { plugin.perform(.preview) }
                    Menu("Actions") {
                        Button("Show in Finder") { plugin.perform(.reveal) }
                        Divider()
                        Button("Copy File") { plugin.perform(.copyFile) }
                        Button("Copy Path") { plugin.perform(.copyPath) }
                    }
                    .menuStyle(.borderlessButton)
                    Button { plugin.perform(.open) } label: {
                        HStack(spacing: 6) {
                            Text("Open")
                            Text("↩").foregroundStyle(.white.opacity(0.75)).accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 10)
    }

    private var hasSearchInput: Bool {
        !plugin.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !plugin.extensionFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !plugin.typeFilter.isEmpty
    }

    private var indexSummary: (isIndexing: Bool, hasIssue: Bool) {
        var isIndexing = false
        var hasIssue = false
        for root in plugin.scopedRoots {
            switch plugin.rootStatus[root.id] {
            case .building, .updating: isIndexing = true
            case .failed: hasIssue = true
            case .ready, nil: break
            }
        }
        return (isIndexing, hasIssue)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Search Folder", selection: $plugin.scope) {
                Text("All Search Folders").tag("")
                ForEach(plugin.settings.roots) { Text($0.url.lastPathComponent).tag($0.id.uuidString) }
            }
            Picker("Type", selection: $plugin.typeFilter) {
                Text("All Types").tag("")
                Text("Files").tag("file")
                Text("Folders").tag("folder")
            }
            Picker("Sort", selection: $plugin.sort) {
                Text("Relevance").tag(FileSearchSort.relevance)
                Text("Name").tag(FileSearchSort.name)
                Text("Modified").tag(FileSearchSort.modified)
            }
        } label: {
            Label("Filters", systemImage: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Search folder, type, and sort order")
    }

    private var hasActiveFilters: Bool {
        !plugin.scope.isEmpty || !plugin.typeFilter.isEmpty || !plugin.extensionFilter.isEmpty || plugin.sort != .relevance
    }

    private var filterSummary: String {
        var parts: [String] = []
        if let root = plugin.settings.roots.first(where: { $0.id.uuidString == plugin.scope }) {
            parts.append(String(localized: "Search Folder") + ": " + root.url.path)
        }
        if !plugin.typeFilter.isEmpty {
            parts.append(String(localized: "Type") + ": " + (plugin.typeFilter == "folder"
                ? String(localized: "Folders") : String(localized: "Files")))
        }
        if !plugin.extensionFilter.isEmpty {
            parts.append(String(localized: "Extension") + ": " + plugin.extensionFilter)
        }
        if plugin.sort != .relevance {
            parts.append(String(localized: "Sort") + ": " + (plugin.sort == .name
                ? String(localized: "Name") : String(localized: "Modified")))
        }
        return parts.joined(separator: " · ")
    }

    private var isSelectionInCloud: Bool {
        guard let file = plugin.selectedFile,
              let root = plugin.settings.roots.first(where: { $0.id == file.rootID }) else { return false }
        let path = root.url.appending(path: file.path).path
        return path.contains("/Library/Mobile Documents/") || path.contains("/Library/CloudStorage/")
    }
}

@MainActor final class FileSearchPanel: TransientPanel {
    var navigate: ((Int) -> Void)?
    var dismiss: (() -> Void)?
    var performAction: ((FileSearchActions.Action) -> Void)?
    var canPreview: (() -> Bool)?
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

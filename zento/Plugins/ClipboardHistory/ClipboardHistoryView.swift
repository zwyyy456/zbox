import SwiftUI

struct ClipboardHistoryView: View {
    @Bindable var plugin: ClipboardHistoryPlugin
    @FocusState private var searchFocused: Bool

    var body: some View {
        let hasSelection = plugin.selectedID != nil
        VStack(spacing: 0) {
            ToolSearchBar {
                TextField("Search Clipboard History", text: $plugin.query)
                    .focused($searchFocused)
                    .onSubmit { plugin.pasteSelection() }
            } accessory: {
                Picker("Filter", selection: $plugin.filter) {
                    ForEach(ClipboardHistoryFilter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .controlSize(.regular)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    List(selection: $plugin.selectedID) {
                        ForEach(Array(plugin.entries.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 10) {
                                ClipboardHistoryRowImage(plugin: plugin, entry: entry)
                                Text(entry.title.prefix(256).split(whereSeparator: \.isWhitespace).joined(separator: " "))
                                    .lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 4)
                                if entry.fileURLs.count > 1 {
                                    Text("\(entry.fileURLs.count) items").font(.caption).foregroundStyle(.secondary)
                                }
                                if entry.pinned { Image(systemName: "pin.fill").font(.caption).accessibilityLabel("Pinned") }
                                if index < 9 {
                                    Text("⌘\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 6)
                            .listRowSeparator(.hidden)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Paste") { plugin.selectedID = entry.id; plugin.pasteSelection() }
                                Button("Copy") { plugin.selectedID = entry.id; plugin.copySelection() }
                                Button(entry.pinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                                    plugin.selectedID = entry.id
                                    plugin.togglePin()
                                }
                                Divider()
                                Button("Delete", role: .destructive) { plugin.selectedID = entry.id; plugin.deleteSelection() }
                            }
                        }
                        if plugin.hasMoreEntries {
                            Button("Load More", action: plugin.loadMore).listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.inset)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    if geometry.size.width >= 640 {
                        Divider()
                        ScrollView {
                            if let entry = plugin.entries.first(where: { $0.id == plugin.selectedID }) {
                                VStack(alignment: .leading, spacing: 20) {
                                    if ["png", "tiff"].contains(entry.kind) {
                                        if let image = plugin.previewImage {
                                            Image(nsImage: image).resizable().scaledToFit()
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.58)
                                                .accessibilityLabel(entry.text)
                                        } else {
                                            Text("Image preview unavailable").foregroundStyle(.secondary)
                                        }
                                    } else if entry.kind == "files" {
                                        LazyVStack(alignment: .leading, spacing: 16) {
                                            if entry.fileURLs.count > 1 {
                                                Text("\(entry.fileURLs.count) items").font(.headline)
                                            }
                                            ForEach(Array(entry.fileURLs.enumerated()), id: \.offset) { _, url in
                                                ClipboardFileReferencePreview(url: url, isPresented: plugin.isPresented,
                                                    maximumHeight: geometry.size.height * 0.58)
                                            }
                                            Text("References only. File and folder contents are not stored.")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Text(entry.text).textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    ClipboardHistoryInformation(entry: entry, dimensions: plugin.previewDimensions)
                                }.padding(16)

                            }
                        }
                        .padding(.vertical, 8)
                        .frame(width: geometry.size.width * 0.62)
                    }
                }
                .overlay {
                    if plugin.entries.isEmpty {
                        ContentUnavailableView("No Clipboard Items", systemImage: "clipboard",
                            description: Text("Copy something after enabling Clipboard History, or change your search and filter."))
                    }
                }
            }
            VStack(spacing: 0) {
                Divider()
                if let message = plugin.statusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 8)
                }
                HStack(spacing: 12) {
                    Text("Clipboard History").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Menu("Actions") {
                        Button("Copy", action: plugin.copySelection).disabled(!hasSelection)
                        Button(plugin.entries.first(where: { $0.id == plugin.selectedID })?.pinned == true
                               ? String(localized: "Unpin") : String(localized: "Pin"), action: plugin.togglePin).disabled(!hasSelection)
                        Divider()
                        Button("Delete", role: .destructive, action: plugin.deleteSelection).disabled(!hasSelection)
                        Divider()
                        Button("Close", action: plugin.dismiss)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    Button(action: plugin.pasteSelection) {
                        HStack(spacing: 6) {
                            Text("Paste")
                            Text("↩").foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!hasSelection)
                }
                .controlSize(.small)
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(.rect(cornerRadius: CommandPanelAppearance.cornerRadius, style: .continuous))
        .alert("Paste into the Previous App", isPresented: $plugin.showingPastePermission) {
            Button("Open System Settings", action: plugin.openAccessibilitySettings)
            Button("Copy Only", action: plugin.copySelection)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pressing Return or ⌘1–9 pastes into the app you were using. Allow Accessibility for Zento, then reopen Clipboard History from that app and try again. You can still copy without this permission.")
        }
        .onAppear { searchFocused = true }
        .onChange(of: plugin.filter) { plugin.selectedID = plugin.entries.first?.id }
        .onChange(of: plugin.query) { plugin.selectedID = plugin.entries.first?.id }
        .onExitCommand(perform: plugin.dismiss)
    }
}

private struct ClipboardFileReferencePreview: View {
    let url: URL
    let isPresented: Bool
    let maximumHeight: CGFloat
    @State private var image: NSImage?
    @State private var previewUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ClipboardImage.canPreviewFile(url) {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity, maxHeight: maximumHeight)
                        .accessibilityLabel(url.lastPathComponent)
                } else if previewUnavailable {
                    Text("Image preview unavailable").foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            Text(url.lastPathComponent).fontWeight(.medium).textSelection(.enabled)
            Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .task(id: isPresented ? url : nil) {
            image = nil
            previewUnavailable = false
            guard isPresented, ClipboardImage.canPreviewFile(url) else { return }
            do {
                let data = try await ClipboardImage.fileThumbnail(url)
                try Task.checkCancellation()
                image = NSImage(data: data)
                previewUnavailable = image == nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                previewUnavailable = true
            }
        }
        .onDisappear { image = nil }
    }
}

private struct ClipboardHistoryRowImage: View {
    let plugin: ClipboardHistoryPlugin
    let entry: ClipboardEntry
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: ["png", "tiff"].contains(entry.kind) ? "photo" : (entry.kind == "link" ? "link" : "doc.text"))
                    .font(.title3).foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
        .task(id: plugin.isPresented) {
            image = nil
            guard plugin.isPresented else { return }
            if let url = entry.fileURLs.first {
                image = NSWorkspace.shared.icon(forFile: url.path)
                return
            }
            guard ["png", "tiff"].contains(entry.kind) else { return }
            image = await plugin.rowThumbnail(for: entry.id)
        }
        .onDisappear { image = nil }
    }
}

private struct ClipboardHistoryInformation: View {
    let entry: ClipboardEntry
    let dimensions: String?
    @State private var sourceName = String(localized: "Unknown Application")
    @State private var sourceIcon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HStack {
                Text("Source Application").foregroundStyle(.secondary)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    if let sourceIcon { Image(nsImage: sourceIcon).resizable().frame(width: 16, height: 16) }
                    Text(sourceName).lineLimit(1).truncationMode(.middle).help(sourceName)
                }
            }
            if let dimensions {
                HStack {
                    Text("Dimensions").foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(dimensions)
                }
            }
            HStack {
                Text(entry.kind == "files" ? String(localized: "Reference Size") : String(localized: "Size")).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
            }
        }
        .font(.callout)
        .task(id: entry.sourceBundleID) {
            sourceIcon = nil
            sourceName = String(localized: "Unknown Application")
            guard let id = entry.sourceBundleID else { return }
            sourceName = id
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                sourceName = FileManager.default.displayName(atPath: url.path)
                sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
    }
}

struct ClipboardHistorySettingsView: View {
    @Bindable var plugin: ClipboardHistoryPlugin
    let onEnabledChanged: @MainActor @Sendable (Bool) -> Void
    let shortcutError: String?
    @State private var confirmsClear = false

    var body: some View {
        Form {
            Toggle("Enable Clipboard History", isOn: Binding(get: { plugin.isEnabled }, set: onEnabledChanged))
            Text("Stores future copies on this Mac. History is not encrypted or synced. Sensitive markers and excluded apps are skipped, but not all secrets can be detected.")
                .foregroundStyle(.secondary)
            if let message = plugin.statusMessage { Text(message).foregroundStyle(.secondary) }
            if let shortcutError { SettingsErrorView(message: shortcutError) }
            if !plugin.isEnabled {
                Label("Recording Disabled", systemImage: "pause.circle").foregroundStyle(.secondary)
            } else if plugin.isRecording {
                Label("Recording Clipboard Changes", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else if plugin.needsClipboardAccess {
                Button("Allow Clipboard Access", action: plugin.requestClipboardAccess)
            } else {
                Button("Resume Recording", action: plugin.start)
            }
            Picker("Keep History", selection: $plugin.retentionDays) {
                Text("1 Day").tag(1)
                Text("7 Days").tag(7)
                Text("30 Days").tag(30)
                Text("Forever").tag(0)
            }
            Picker("Storage Limit", selection: Binding(get: { plugin.storageLimitMiB }, set: plugin.setStorageLimitMiB)) {
                Text("Unlimited").tag(0)
                Text("100 MiB").tag(100)
                Text("500 MiB").tag(500)
                Text("1 GiB").tag(1024)
                Text("5 GiB").tag(5120)
            }
            LabeledContent("Stored Content", value: ByteCountFormatter.string(fromByteCount: Int64(plugin.storedBytes), countStyle: .binary))
            Text("No item count limit. When the storage limit is reached, the oldest unpinned items are removed. Pinned items never expire and count toward storage. Lowering the limit removes older items immediately.")
                .font(.caption).foregroundStyle(.secondary)
            Section("Excluded Applications") {
                ForEach(plugin.excludedApplications.sorted(), id: \.self) { id in
                    HStack {
                        Text(id).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { plugin.removeExcludedApplication(id) }
                    }
                }
                Button("Add Application…", action: plugin.chooseExcludedApplication)
            }
            Section("Paste into the Previous App") {
                Text("Open Clipboard History with its shortcut, select an item, and press Return to paste. Use ⌘1–9 for the first nine displayed items, or ⌘Return to copy only.")
                    .foregroundStyle(.secondary)
                Text("Accessibility is required only to paste into another app. Browsing and copying remain available without it.")
                    .font(.caption).foregroundStyle(.secondary)
                AccessibilityPermissionRow(isTrusted: plugin.isPasteTrusted,
                                           request: plugin.requestPastePermission,
                                           openSettings: plugin.openAccessibilitySettings)
            }
            Button("Clear Clipboard History…", role: .destructive) { confirmsClear = true }
        }
        .settingsPane()
        .onAppear { plugin.refreshStorageUsage() }
        .confirmationDialog("Delete all clipboard history, including pinned items?", isPresented: $confirmsClear) {
            Button("Delete All", role: .destructive, action: plugin.clearHistory)
        }
    }
}

import SwiftUI

struct RootSearchView: View {
    let environment: AppEnvironment

    @State private var isSearchFocused = false

    var body: some View {
        @Bindable var session = environment.rootSearch
        let sections = environment.rootSearch.searchResultSections
        let selected = environment.rootSearch.selectedSearchMatch
        let actions = selected.map { environment.rootSearchActions(for: $0.id) } ?? []

        VStack(spacing: 0) {
            NativeSearchField(title: String(localized: "Search apps and commands"),
                              text: $session.searchQuery, isFocused: $isSearchFocused,
                              moveSelection: environment.moveSelection)
                .controlSize(.large)
                .padding(18)

            Divider()

            if sections.isEmpty {
                ContentUnavailableView(
                    "No Commands Found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different application or command name.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: { session.selectedSearchMatch?.id },
                        set: { session.selectedCommandID = $0 }
                    )) {
                        ForEach(sections) { section in
                            Section {
                                if let title = section.title {
                                    Text(title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .accessibilityAddTraits(.isHeader)
                                        .selectionDisabled()
                                        .listRowSeparator(.hidden)
                                }
                                ForEach(section.matches) { match in
                                    resultButton(match)
                                        .tag(match.id)
                                        .listRowSeparator(.hidden)
                                }
                            }
                            .listSectionSeparator(.hidden)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .onChange(of: selected?.id) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if environment.rootSearch.isShowingRootSearchActions, !actions.isEmpty {
                        RootSearchActionsList(actions: actions,
                                              selectedIndex: $session.selectedRootSearchActionIndex,
                                              perform: environment.performRootSearchAction)
                            .padding(10)
                    }
                }
            }

            Divider()

            footer(selected: selected, hasActions: !actions.isEmpty)
        }
        .frame(width: 640, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(
            .rect(
                cornerRadius: CommandPanelAppearance.cornerRadius,
                style: .continuous
            )
        )
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            environment.hideRootSearch()
        }
    }

    private func resultButton(_ match: SearchMatch) -> some View {
        Button {
            environment.rootSearch.select(match.id)
            environment.executeSelectedCommand()
        } label: {
            CommandResultRow(
                match: match,
                icon: environment.applicationIcon(for: match.id),
                subtitle: environment.subtitle(for: match.descriptor),
                accessory: environment.accessoryTitle(for: match.descriptor),
                alias: environment.aliasStore.aliases[match.id],
                hotkey: environment.commandHotkey(for: match.id).map(HotkeyFormatter.displayName(for:))
            )
        }
        .id(match.id)
        .buttonStyle(.plain)
        .accessibilityLabel(match.descriptor.title)
    }

    @ViewBuilder
    private func footer(selected: SearchMatch?, hasActions: Bool) -> some View {
        HStack(spacing: 14) {
            Menu {
                ApplicationMenuItems(environment: environment)
            } label: {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable().scaledToFit().frame(width: 18, height: 18)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Zento Menu")
            .accessibilityLabel("Zento Menu")
            if let feedback = environment.rootSearch.commandFeedback {
                VStack(alignment: .leading, spacing: 6) {
                    Label(feedback.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if let recovery = feedback.recoveryAction {
                        Button(recovery.title) { environment.performCommandRecovery(recovery) }
                            .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
                if let selected {
                    KeyHint(title: environment.primaryActionTitle(for: selected.descriptor), key: "↩")
                }
                if hasActions {
                    Button {
                        environment.rootSearch.isShowingRootSearchActions.toggle()
                    } label: {
                        KeyHint(title: String(localized: "Actions"), key: "⌘K")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Actions")
                    .accessibilityValue(environment.rootSearch.isShowingRootSearchActions
                        ? String(localized: "Expanded") : String(localized: "Collapsed"))
                }
                KeyHint(title: String(localized: "Close"), key: "esc")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct KeyHint: View {
    let title: String
    let key: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text(key)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: .rect(cornerRadius: 4))
        }
    }
}

private struct RootSearchActionsList: View {
    let actions: [RootSearchAction]
    @Binding var selectedIndex: Int
    let perform: (RootSearchAction) -> Void

    var body: some View {
        List(selection: Binding<Int?>(
            get: { selectedIndex },
            set: { if let index = $0 { selectedIndex = index } }
        )) {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                Button { perform(action) } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .tag(index)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .frame(width: 240, height: CGFloat(actions.count) * 32 + 16)
        .clipShape(.rect(cornerRadius: 10))
        .shadow(radius: 8)
        .accessibilityLabel("Actions")
    }
}

private struct CommandResultRow: View {
    let match: SearchMatch
    let icon: NSImage?
    let subtitle: String?
    let accessory: String
    let alias: String?
    let hotkey: String?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: match.descriptor.systemImage ?? "command")
                        .resizable()
                        .padding(5)
                }
            }
            .scaledToFit()
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(match.descriptor.title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 12)

            if let alias { Text(alias).font(.caption.monospaced()).foregroundStyle(.secondary) }
            if let hotkey {
                Text(hotkey)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary,
                                in: .rect(cornerRadius: 4))
            }
            Text(accessory)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

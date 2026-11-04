import SwiftUI

struct RootSearchView: View {
    let environment: AppEnvironment

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var environment = environment
        let sections = environment.searchResultSections
        let selected = environment.selectedSearchMatch
        let actions = selected.map { environment.rootSearchActions(for: $0.id) } ?? []

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search apps and commands", text: $environment.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
            }
            .font(.title2)
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
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(sections) { section in
                                if let title = section.title {
                                    Text(title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 8)
                                        .padding(.bottom, 2)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                ForEach(section.matches) { match in
                                    resultButton(match, isSelected: match.id == selected?.id)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selected?.id) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if environment.isShowingRootSearchActions, !actions.isEmpty {
                        RootSearchActionsList(actions: actions,
                                              selectedIndex: environment.selectedRootSearchActionIndex,
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

    private func resultButton(_ match: SearchMatch, isSelected: Bool) -> some View {
        Button {
            environment.select(match.id)
            environment.executeSelectedCommand()
        } label: {
            CommandResultRow(
                match: match,
                icon: environment.applicationIcon(for: match.id),
                subtitle: environment.subtitle(for: match.descriptor),
                accessory: environment.accessoryTitle(for: match.descriptor),
                alias: environment.aliasStore.aliases[match.id],
                hotkey: environment.commandHotkey(for: match.id).map(HotkeyFormatter.displayName(for:)),
                isSelected: isSelected
            )
        }
        .id(match.id)
        .buttonStyle(.plain)
        .accessibilityLabel(match.descriptor.title)
        .accessibilityValue(isSelected ? String(localized: "Selected") : "")
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
            if let feedback = environment.commandFeedback {
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
                        environment.isShowingRootSearchActions.toggle()
                    } label: {
                        KeyHint(title: String(localized: "Actions"), key: "⌘K")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Actions")
                    .accessibilityValue(environment.isShowingRootSearchActions
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
    let selectedIndex: Int
    let perform: (RootSearchAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                Button { perform(action) } label: {
                    HStack {
                        Label(action.title, systemImage: action.systemImage)
                        Spacer()
                        if index == selectedIndex { Text(verbatim: "↩") }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(.rect)
                    .background(index == selectedIndex ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear, in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityValue(index == selectedIndex ? String(localized: "Selected") : "")
            }
        }
        .padding(6)
        .frame(width: 240)
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 10))
        .shadow(radius: 8)
        .accessibilityElement(children: .contain)
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
    let isSelected: Bool

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
        .background(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : Color.clear, in: .rect(cornerRadius: 8))
    }
}

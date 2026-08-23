import SwiftUI

struct RootSearchView: View {
    let environment: AppEnvironment

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var environment = environment

        VStack(spacing: 0) {
            TextField("Search applications", text: $environment.searchQuery)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isSearchFocused)
                .padding(18)

            Divider()

            if environment.searchResults.isEmpty {
                ContentUnavailableView(
                    "No Commands Found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different application or command name.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(environment.searchResults) { match in
                            Button {
                                environment.select(match.id)
                                environment.executeSelectedCommand()
                            } label: {
                                CommandResultRow(
                                    match: match,
                                    icon: environment.applicationIcon(for: match.id),
                                    systemImage: environment.systemImage(for: match.id),
                                    subtitle: environment.subtitle(for: match.descriptor),
                                    isSelected: environment.isSelected(match.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(match.descriptor.title)
                            .accessibilityValue(
                                environment.isSelected(match.id) ? "Selected" : ""
                            )
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack {
                Text(environment.commandFeedback?.message ?? environment.statusMessage)
                    .lineLimit(1)
                Spacer()
                if let recovery = environment.commandFeedback?.recoveryAction {
                    switch recovery {
                    case .openAccessibilitySettings:
                        Button("Open Accessibility Settings") {
                            environment.performCommandRecovery(recovery)
                        }
                        .buttonStyle(.link)
                    case .openWindowManagementSettings:
                        Button("Open Window Management") {
                            environment.performCommandRecovery(recovery)
                        }
                        .buttonStyle(.link)
                    }
                } else {
                    Text("↑↓ Select   ↩ Run   esc Close")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 640, height: 420)
        .background(.regularMaterial)
        .clipShape(
            .rect(
                cornerRadius: RootSearchAppearance.cornerRadius,
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
}
private struct CommandResultRow: View {
    let match: SearchMatch
    let icon: NSImage?
    let systemImage: String?
    let subtitle: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: systemImage ?? "command")
                        .resizable()
                        .padding(5)
                }
            }
            .scaledToFit()
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(match.descriptor.title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(.rect)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(.rect(cornerRadius: 8))
    }
}

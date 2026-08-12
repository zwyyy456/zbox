import SwiftUI

struct M0CheckView: View {
    let environment: AppEnvironment

    @FocusState private var isSearchFocused: Bool

    private var filteredApplications: [ApplicationInfo] {
        let candidates = environment.applications
        guard !environment.searchQuery.isEmpty else { return Array(candidates.prefix(8)) }

        return candidates
            .filter { $0.name.localizedCaseInsensitiveContains(environment.searchQuery) }
            .prefix(8)
            .map(\.self)
    }

    var body: some View {
        @Bindable var environment = environment

        VStack(spacing: 0) {
            TextField("Search applications", text: $environment.searchQuery)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isSearchFocused)
                .padding(18)

            Divider()

            HStack {
                Button("Left Half", systemImage: "rectangle.lefthalf.inset.filled") {
                    environment.performWindowAction(.leftHalf)
                }
                Button("Right Half", systemImage: "rectangle.righthalf.inset.filled") {
                    environment.performWindowAction(.rightHalf)
                }
                Button("Maximize", systemImage: "rectangle.inset.filled") {
                    environment.performWindowAction(.maximize)
                }

                Spacer()

                Button("Reload", systemImage: "arrow.clockwise") {
                    environment.reloadApplications()
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            List(filteredApplications) { application in
                Button {
                    environment.launch(application)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(application.name)
                        Text(application.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)

            Divider()

            Text(environment.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 640, height: 420)
        .background(.regularMaterial)
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            environment.hideRootSearch()
        }
    }
}

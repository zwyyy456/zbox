import SwiftUI

struct DeveloperToolsView: View {
    @Bindable var plugin: DeveloperToolsPlugin

    var body: some View {
        HStack(spacing: 0) {
            List(DeveloperToolsPlugin.Tool.allCases, selection: $plugin.selection) { tool in
                Label(tool.title, systemImage: tool.icon).tag(tool)
            }
            .listStyle(.sidebar)
            .frame(width: 180)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text(plugin.selection.title).font(.title2)
                switch plugin.selection {
                case .json: DeveloperTextToolView(session: plugin.jsonSession, copy: plugin.copy).id(plugin.selection)
                case .timestamp: DeveloperTimestampView(session: plugin.timestampSession, copy: plugin.copy)
                case .uuid: uuidView
                case .url: DeveloperTextToolView(session: plugin.urlSession, copy: plugin.copy).id(plugin.selection)
                case .base64: DeveloperTextToolView(session: plugin.base64Session, copy: plugin.copy).id(plugin.selection)
                }
                if let error = plugin.copyError {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var uuidView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Stepper("Count: \(plugin.uuidCount)", value: $plugin.uuidCount, in: 1...100)
                    .fixedSize()
                Toggle("Uppercase", isOn: $plugin.uppercaseUUIDs)
                Spacer()
                Button("Generate") { plugin.generateUUIDs() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Text("UUID v4 · One UUID per line")
                .font(.caption).foregroundStyle(.secondary)
            List(plugin.uuids, id: \.self) { uuid in
                HStack {
                    Text(plugin.uuidText(uuid)).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("Copy") { plugin.copy(plugin.uuidText(uuid)) }
                }
            }
            Button("Copy All") { plugin.copy(plugin.uuids.map(plugin.uuidText).joined(separator: "\n")) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(plugin.uuids.isEmpty)
        }
    }
}

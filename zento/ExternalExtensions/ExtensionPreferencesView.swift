import SwiftUI

struct ExtensionPreferencesView: View {
    let item: ExtensionInstallation
    @Bindable var manager: ExtensionManager
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var grants: Set<String> = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.manifest.name).font(.title2)
            Form {
                Section("Host Capabilities") {
                    ForEach(item.manifest.capabilities ?? [], id: \.self) { capability in
                        Toggle(ExtensionManifest.capabilityLabel(capability), isOn: Binding(get: { grants.contains(capability) }, set: { enabled in
                            if enabled { grants.insert(capability) } else { grants.remove(capability) }
                        }))
                    }
                }
                ForEach(item.manifest.settings ?? []) { field in
                    let text = Binding(get: { values[field.id] ?? field.defaultValue ?? "" }, set: { values[field.id] = $0 })
                    switch field.type {
                    case "secret": SecureField(field.name, text: text)
                    case "boolean": Toggle(field.name, isOn: Binding(get: { text.wrappedValue == "true" }, set: { text.wrappedValue = $0 ? "true" : "false" }))
                    case "choice": Picker(field.name, selection: text) { ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) } }
                    default: TextField(field.name, text: text)
                    }
                }
            }.formStyle(.grouped)
            Text("Saving ends the current extension session. Credentials are stored in Keychain.").font(.caption).foregroundStyle(.secondary)
            if let error = error ?? manager.error { SettingsErrorView(message: error) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if loading || manager.busy { ProgressView().controlSize(.small) }
                Button("Save") {
                    Task { if await manager.savePreferences(item, values: values, grants: Array(grants)) { dismiss() } }
                }.disabled(loading || manager.busy || error != nil)
            }
        }.padding(20).frame(width: 520, height: 460)
        .task {
            grants = Set(item.grants)
            do {
                let data = manager.dataStore(item.id)
                values = try await data.settings()
                for field in item.manifest.settings ?? [] where field.type == "secret" {
                    values[field.id] = try await data.credential(field.id) ?? ""
                }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

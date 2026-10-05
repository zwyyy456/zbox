import ZboxExtensionProtocol
import SwiftUI

struct ExtensionSessionView: View {
    @Bindable var session: ExtensionSession
    @State private var confirming: ExtensionAction?
    @State private var confirmationRevision = 0
    var body: some View {
        let revision = session.viewRevision
        VStack(alignment: .leading, spacing: 12) {
            if !session.ready {
                ForEach(Array((session.command.parameters ?? []).enumerated()), id: \.element.id) { index, field in
                    TextField(field.name, text: $session.values[index]).disabled(session.running)
                }
            }
            HStack {
                Text(session.snapshot.title ?? session.command.name).font(.title2)
                Spacer()
                if session.snapshot.loading == true || (session.running && !session.ready) { ProgressView().controlSize(.small) }
                if !session.running { Button("Run", action: session.start) }
                Button("Stop", action: session.cancel).disabled(!session.running)
            }
            if session.snapshot.searchable == true {
                TextField("Search", text: Binding(get: { session.query }, set: session.sendQuery))
                    .textFieldStyle(.roundedBorder).disabled(!session.ready)
            }
            HSplitView {
                if let items = session.snapshot.items {
                    List(items, selection: $session.selectedID) { item in
                        VStack(alignment: .leading) {
                            Text(item.title)
                            if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                        }.tag(item.id)
                    }.overlay { if items.isEmpty { Text("No Results").foregroundStyle(.secondary) } }
                    .frame(minWidth: 180)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let detail = session.snapshot.detail { Text(detail).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        ForEach(session.snapshot.fields ?? []) { field in
                            fieldView(field)
                            if let error = field.error { Text(error).font(.caption).foregroundStyle(.red) }
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minWidth: 240)
            }.frame(maxHeight: .infinity)
            if let message = session.snapshot.message { Text(message).font(.callout) }
            if let error = session.error ?? session.snapshot.error { SettingsErrorView(message: error) }
            if session.needsAccessibility {
                Button("Open Accessibility Settings") { AccessibilityAuthorization().openSystemSettings() }
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array((session.snapshot.actions ?? []).enumerated()), id: \.element.id) { index, action in
                        if index == 0 {
                            Button(action.title) { invoke(action, revision: revision) }.keyboardShortcut(.return, modifiers: .command)
                                .disabled(!session.ready || action.enabled == false)
                        } else {
                            Button(action.title) { invoke(action, revision: revision) }.disabled(!session.ready || action.enabled == false)
                        }
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
        }.padding(20)
        .confirmationDialog(confirming?.title ?? "Confirm", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            if let action = confirming { Button(action.title, role: .destructive) { session.perform(action, revision: confirmationRevision); confirming = nil } }
        }
    }

    private func invoke(_ action: ExtensionAction, revision: Int) {
        if action.destructive == true { confirmationRevision = revision; confirming = action } else { session.perform(action, revision: revision) }
    }

    @ViewBuilder private func fieldView(_ field: ExtensionField) -> some View {
        let text = Binding(get: { session.fieldValues[field.id] ?? "" }, set: { session.fieldValues[field.id] = $0 })
        Group {
            switch field.type {
            case "multiline":
                Text(field.name).font(.headline)
                PlainTextEditor(text: text, label: field.name).frame(minHeight: 100)
            case "boolean":
                Toggle(field.name, isOn: Binding(get: { text.wrappedValue == "true" }, set: { text.wrappedValue = $0 ? "true" : "false" }))
            case "choice":
                Picker(field.name, selection: text) { ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) } }
            default: TextField(field.name, text: text).textFieldStyle(.roundedBorder)
            }
        }.disabled(!session.ready)
    }
}

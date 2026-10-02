import SwiftUI

struct DeveloperTextToolView: View {
    @Bindable var session: DeveloperTextSession
    let copy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Operation", selection: $session.decoding) {
                    Text("Encode").tag(false)
                    Text("Decode").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 220)
                if session.kind == .base64 {
                    Picker("Alphabet", selection: $session.urlSafe) {
                        Text("Standard Base64").tag(false)
                        Text("URL-safe Base64").tag(true)
                    }.labelsHidden()
                }
                Spacer()
                Button("Run") { session.run() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Text(session.kind == .url
                 ? String(localized: "URL components · Spaces use %20; + stays a plus sign when decoding.")
                 : String(localized: "UTF-8 text · Standard output is padded; URL-safe output omits padding."))
                .font(.caption).foregroundStyle(.secondary)
            HSplitView {
                VStack(alignment: .leading) {
                    Text("Input").font(.headline)
                    DeveloperTextEditor(text: $session.input, label: String(localized: "Input"))
                }.frame(minWidth: 180, maxWidth: .infinity)
                VStack(alignment: .leading) {
                    Text("Output").font(.headline)
                    DeveloperTextEditor(text: .constant(session.output ?? ""), isEditable: false,
                                        label: String(localized: "Output"))
                }.frame(minWidth: 180, maxWidth: .infinity)
            }
            if let error = session.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            } else if session.isRunning {
                ProgressView().controlSize(.small)
            } else if session.output == nil {
                Text("Run to update the result.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Clear") { session.input = "" }
                Button("Use Result as Input") {
                    if let output = session.output { session.input = output }
                }.disabled(session.output == nil)
                Spacer()
                Button("Copy Result") { if let output = session.output { copy(output) } }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(session.output == nil)
            }
        }
    }
}

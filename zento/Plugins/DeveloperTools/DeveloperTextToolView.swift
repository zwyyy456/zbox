import SwiftUI

struct DeveloperTextToolView: View {
    @Bindable var session: DeveloperTextSession
    let copy: (String) -> Void
    @State private var selectionRequest: (id: UUID, offset: Int)?

    private var hint: String {
        switch session.kind {
        case .json: String(localized: "Standard JSON · Formatting preserves numbers, key order, and string escapes.")
        case .url: String(localized: "URL components · Spaces use %20; + stays a plus sign when decoding.")
        case .base64: String(localized: "UTF-8 text · Standard output is padded; URL-safe output omits padding.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if session.kind == .json {
                    Picker("Indent", selection: $session.indentation) {
                        Text("2 spaces").tag(2)
                        Text("4 spaces").tag(4)
                    }
                    Spacer()
                    Button(JSONFormatter.Operation.format.title) {
                        session.jsonOperation = .format
                        session.run()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    Button(JSONFormatter.Operation.compact.title) {
                        session.jsonOperation = .compact
                        session.run()
                    }
                    Button(JSONFormatter.Operation.validate.title) {
                        session.jsonOperation = .validate
                        session.run()
                    }
                } else {
                    if session.kind == .base64 {
                        Picker("Alphabet", selection: $session.urlSafe) {
                            Text("Standard Base64").tag(false)
                            Text("URL-safe Base64").tag(true)
                        }.labelsHidden()
                    }
                    Spacer()
                    Button("Encode") {
                        session.decoding = false
                        session.run()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    Button("Decode") {
                        session.decoding = true
                        session.run()
                    }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                }
            }
            Text(hint).font(.caption).foregroundStyle(.secondary)
            VSplitView {
                VStack(alignment: .leading) {
                    Text("Input").font(.headline)
                    PlainTextEditor(text: $session.input, label: String(localized: "Input"),
                                        selectionRequest: selectionRequest)
                }.frame(minHeight: 120, maxHeight: .infinity)
                VStack(alignment: .leading) {
                    Text("Output").font(.headline)
                    PlainTextEditor(text: .constant(session.output ?? ""), isEditable: false,
                                        label: String(localized: "Output"))
                }.frame(minHeight: 120, maxHeight: .infinity)
            }
            if let error = session.error {
                HStack(alignment: .top) {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    if let offset = session.errorOffset {
                        Button("Go to Error") { selectionRequest = (UUID(), offset) }
                    }
                }
            } else if session.isRunning {
                ProgressView().controlSize(.small)
            } else if session.validated {
                Text("Valid JSON syntax.").foregroundStyle(.secondary)
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

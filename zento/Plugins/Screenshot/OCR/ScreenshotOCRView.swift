import SwiftUI

struct ScreenshotOCRView: View {
    let document: ScreenshotDocument
    let copy: (String) -> Void

    var body: some View {
        @Bindable var session = document.ocr
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Recognition Language", selection: $session.language) {
                    Text("Automatic").tag("")
                    ForEach(ScreenshotTextRecognizer.languages, id: \.self) { language in
                        Text(Locale.current.localizedString(forIdentifier: language) ?? language).tag(language)
                    }
                }.frame(maxWidth: 280)
                Toggle("Language Correction", isOn: $session.correction)
                Spacer()
                Button("Recognize Again") { session.run(image: document.image, edit: document.edit) }
                    .disabled(session.isRunning)
            }
            TextEditor(text: $session.text).font(.system(.body, design: .monospaced))
                .autocorrectionDisabled().disabled(!session.hasResult)
                .accessibilityLabel("Recognized Text")
            HStack {
                if session.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { session.invalidate() }
                } else if let error = session.error {
                    Text(error).foregroundStyle(.red)
                } else if session.hasResult && session.text.isEmpty {
                    Text("No text was found.").foregroundStyle(.secondary)
                } else if !session.hasResult {
                    Text("Recognize again after changing the image or options.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy Text") { copy(session.text) }.disabled(!session.hasResult || session.text.isEmpty)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }.padding()
    }
}

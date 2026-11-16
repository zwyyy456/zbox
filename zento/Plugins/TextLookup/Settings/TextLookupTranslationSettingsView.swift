import SwiftUI

struct TextLookupTranslationSettingsView: View {
    let settings: TextLookupTranslationSettings
    @State private var draft = TextLookupTranslationConfiguration()
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var saved = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Translation Service", selection: $draft.provider) {
                ForEach(TextLookupTranslationProvider.allCases) { provider in Text(provider.name).tag(provider) }
            }
            if draft.provider == .deepl {
                Picker("DeepL API", selection: $draft.deepLEndpoint) {
                    Text("DeepL API Free").tag("https://api-free.deepl.com/v2/translate")
                    Text("DeepL API Pro").tag("https://api.deepl.com/v2/translate")
                }
            } else if draft.provider == .openAICompatible {
                TextField("Chat Completions URL", text: $draft.openAIEndpoint)
                TextField("Model", text: $draft.model)
            }
            if draft.provider != .apple {
                SecureField("API Key — leave empty to keep the saved key", text: $apiKey)
                Text("The original sentence is sent to the selected service when you look up text. API keys are stored only in Zento’s Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Delete Saved API Key", role: .destructive) {
                    isSaving = true
                    Task { _ = await settings.removeCredential(for: draft.provider); isSaving = false; saved = false }
                }
            }
            HStack {
                Button("Save Translation Settings") {
                    isSaving = true
                    let configuration = draft, key = apiKey
                    Task {
                        saved = await settings.save(configuration, apiKey: key)
                        if saved { apiKey = "" }
                        isSaving = false
                    }
                }
                if isSaving { ProgressView().controlSize(.small) }
                else if saved { Text("Saved").font(.caption).foregroundStyle(.secondary) }
            }
            if let error = settings.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .disabled(isSaving)
        .onAppear { draft = settings.snapshot }
        .onChange(of: draft) { saved = false }
        .onChange(of: draft.provider) { apiKey = "" }
    }
}

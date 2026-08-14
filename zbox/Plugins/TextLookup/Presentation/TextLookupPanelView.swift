import SwiftUI

struct TextLookupPanelView: View {
    let model: TextLookupSessionModel
    let settings: TextLookupSettingsStore

    private let languageChoices = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let capture = model.capture {
                HStack(alignment: .firstTextBaseline) {
                    Text(capture.term)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    Spacer(minLength: 16)
                    languageMenu
                }

                if let sentence = capture.sentence {
                    Text(sentence)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }

                Divider()
                pendingRow("Definition", detail: "Looking up in FlashDict…")
                if capture.sentence != nil {
                    pendingRow("Translation", detail: "Preparing translation…")
                }
            } else if let error = model.captureError {
                ContentUnavailableView(
                    "Unable to Look Up Text",
                    systemImage: "text.magnifyingglass",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .padding(18)
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var languageMenu: some View {
        Menu {
            ForEach(languageChoices, id: \.0) { identifier, name in
                Button {
                    settings.setTargetLanguageIdentifier(identifier)
                } label: {
                    if settings.targetLanguageIdentifier == identifier {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            Label(languageName, systemImage: "globe")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Translation target language")
    }

    private var languageName: String {
        languageChoices.first { $0.0 == settings.targetLanguageIdentifier }?.1
            ?? settings.targetLanguageIdentifier
    }

    private func pendingRow(_ title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

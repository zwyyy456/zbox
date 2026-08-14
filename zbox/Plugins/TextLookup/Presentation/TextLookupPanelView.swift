import FlashDictIntegrationKit
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
                dictionaryContent
                if capture.sentence != nil {
                    Divider()
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
        .frame(
            minWidth: 300,
            maxWidth: .infinity,
            minHeight: 180,
            maxHeight: .infinity,
            alignment: .topLeading
        )
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

    @ViewBuilder
    private var dictionaryContent: some View {
        switch model.dictionaryState {
        case .idle, .loading:
            pendingRow("Definition", detail: "Looking up in FlashDict…")
        case .loaded(let document):
            if let resourceProvider = model.resourceProvider {
                FlashDictLookupSurface(
                    document: document,
                    resourceProvider: resourceProvider,
                    selectionStates: model.selectionStates,
                    onEvent: model.handle
                )
                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
            }
            if let surfaceMessage = model.surfaceMessage {
                Text(surfaceMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 8) {
                Label("Definition unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(failure.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if failure.canRetry {
                    HStack {
                        if failure == .flashDictNotRunning {
                            Button("Open FlashDict") {
                                model.openFlashDict()
                            }
                        }
                        Button("Retry") {
                            model.retryDictionaryLookup()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

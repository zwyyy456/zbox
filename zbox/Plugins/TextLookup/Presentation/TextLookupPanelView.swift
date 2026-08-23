import FlashDictIntegrationKit
import SwiftUI
@preconcurrency import Translation

struct TextLookupPanelView: View {
    let model: TextLookupSessionModel
    let settings: TextLookupSettingsStore
    @State private var translationConfiguration: TranslationSession.Configuration?

    private let languageIdentifiers = ["en", "zh-Hans", "ja", "ko", "fr", "de", "es"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.isCapturing {
                pendingRow("Text", detail: "Reading text under the pointer…")
            } else if let capture = model.capture {
                Text(capture.term)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)

                if let sentence = capture.sentence {
                    ScrollView(.vertical) {
                        Text(sentence)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 88)
                }

                Divider()
                translationContent
                Divider()
                dictionaryContent
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
        .onAppear(perform: refreshTranslationConfiguration)
        .onChange(of: model.translationRequest?.id) {
            refreshTranslationConfiguration()
        }
        .translationTask(translationConfiguration) { session in
            guard let request = model.translationRequest else { return }
            switch await Self.runTranslation(session, request: request) {
            case .success(let result):
                model.completeTranslation(result)
            case .failure(let failure):
                model.failTranslation(failure, requestID: request.id)
            case .cancelled:
                model.failTranslation(.modelDownloadCancelled, requestID: request.id)
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(languageChoices, id: \.0) { identifier, name in
                Button {
                    settings.setTargetLanguageIdentifier(identifier)
                    model.requestTranslation(targetLanguageIdentifier: identifier)
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

    @ViewBuilder
    private var translationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Translation")
                    .font(.headline)
                Spacer(minLength: 16)
                languageMenu
            }
            switch model.translationState {
            case .sentenceUnavailable:
                Text("No sentence is available to translate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing Apple Translation…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .translated(let result):
                Text(result.translatedText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let failure):
                VStack(alignment: .leading, spacing: 6) {
                    Text(failure.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Retry Translation") {
                        model.retryTranslation()
                    }
                }
            }
        }
    }

    private func refreshTranslationConfiguration() {
        guard let request = model.translationRequest else {
            translationConfiguration = nil
            return
        }
        if var configuration = translationConfiguration {
            configuration.source = request.sourceLanguage
            configuration.target = request.targetLanguage
            configuration.invalidate()
            translationConfiguration = configuration
        } else {
            translationConfiguration = .init(
                source: request.sourceLanguage,
                target: request.targetLanguage
            )
        }
    }

    nonisolated private static func runTranslation(
        _ session: TranslationSession,
        request: TranslationRequest
    ) async -> AppleTranslationOutcome {
        let status: LanguageAvailability.Status
        do {
            status = try await LanguageAvailability().status(
                for: request.text,
                to: request.targetLanguage
            )
        } catch {
            return .failure(.unableToIdentifyLanguage)
        }
        guard status != .unsupported else {
            return .failure(.unsupportedLanguagePair)
        }
        do {
            try await session.prepareTranslation()
            let response = try await session.translate(request.text)
            return .success(
                TranslationResult(
                    requestID: request.id,
                    sourceLanguage: response.sourceLanguage,
                    targetLanguage: response.targetLanguage,
                    translatedText: response.targetText
                )
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(.internalFailure)
        }
    }

    private var languageName: String {
        languageChoices.first { $0.0 == settings.targetLanguageIdentifier }?.1
            ?? settings.targetLanguageIdentifier
    }

    private var languageChoices: [(String, String)] {
        languageIdentifiers.map { identifier in
            (
                identifier,
                Locale.current.localizedString(forIdentifier: identifier) ?? identifier
            )
        }
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

    private func pendingRow(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
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

private nonisolated enum AppleTranslationOutcome: Sendable {
    case success(TranslationResult)
    case failure(TextLookupTranslationFailure)
    case cancelled
}

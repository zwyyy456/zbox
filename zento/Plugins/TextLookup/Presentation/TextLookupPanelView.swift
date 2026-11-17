import AppKit
import LookupPresentation
import SystemDictionary
import SwiftUI
@preconcurrency import Translation

struct TextLookupPanelView: View {
    let model: TextLookupSessionModel
    let settings: TextLookupSettingsStore
    let onClose: () -> Void
    @State private var translationConfiguration: TranslationSession.Configuration?

    @State private var languageIdentifiers = ["en", "zh-Hans", "ja", "ko", "fr", "de", "es", "pl"]

    var body: some View {
        LookupPanelContent(title: model.activeDictionaryTerm ?? model.capture?.term ?? String(localized: "Text Lookup"),
                           state: model.windowState, onClose: onClose) {
            if let capture = model.capture {
                LookupContextCard {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.isLoadingContext { ProgressView("Reading nearby context…").controlSize(.small) }
                        if let message = model.contextMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                        if let sentence = capture.sentence, !capture.needsContext {
                            LookupContextHeader(isIncomplete: capture.isContextFragment) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(sentence, forType: .string)
                            }
                            LookupSentenceView(sentence: sentence, selectedWord: model.activeDictionaryTerm, onSelectWord: model.selectWord)
                        } else if !model.isLoadingContext && model.contextMessage == nil {
                            Text("No sentence was captured.").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                } translation: { translationContent }
                dictionaryContent
            } else if model.isRecognizingWord {
                ProgressView("Recognizing nearby text…")
                Text("Press Esc to cancel.").font(.caption).foregroundStyle(.secondary)
            } else if let message = model.integrationMessage {
                Label("FlashDict unavailable", systemImage: "exclamationmark.triangle").font(.headline)
                Text(message)
                HStack {
                    Button("Open FlashDict") { TextLookupPlugin.openFlashDict(onFailure: { message in
                        guard settings.dictionarySource == .flashDict, model.integrationMessage != nil else { return }
                        model.integrationMessage = message
                    }) }
                    Button("Retry") { model.retryIntegration?() }
                }
            } else if let error = model.captureError {
                ContentUnavailableView("Unable to Look Up Text", systemImage: "text.magnifyingglass", description: Text(error.localizedDescription))
                if error == .screenCapturePermissionRequired {
                    Button("Open Screen Recording Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
                    }
                }
            }
        }
        .task {
            let languages = await TextLookupTranslationLanguages.supportedIdentifiers()
            guard !Task.isCancelled else { return }
            languageIdentifiers = languages
        }
        .onChange(of: settings.translation.snapshot, requestTranslationUsingSettings)
        .onChange(of: settings.sourceLanguageIdentifier, requestTranslationUsingSettings)
        .onChange(of: settings.targetLanguageIdentifier, requestTranslationUsingSettings)
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
            case .downloadRequired:
                model.requireLanguageDownload(requestID: request.id)
            case .cancelled:
                model.failTranslation(.cancelled, requestID: request.id)
            }
        }
    }

    private func languageMenu(source: Bool) -> some View {
        Menu {
            if source {
                Button("Detect Automatically") { changeLanguage("", source: true) }
                Divider()
            }
            ForEach(languageChoices, id: \.0) { identifier, name in
                Button { changeLanguage(identifier, source: source) } label: {
                    if identifier == (source ? settings.sourceLanguageIdentifier : settings.targetLanguageIdentifier) {
                        Label(name, systemImage: "checkmark")
                    } else { Text(name) }
                }
            }
        } label: {
            Text(source ? sourceLanguageName : languageName(settings.targetLanguageIdentifier))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(source ? String(localized: "Translation source language") : String(localized: "Translation target language"))
        .accessibilityLabel(source ? String(localized: "Translation source language") : String(localized: "Translation target language"))
    }

    private func changeLanguage(_ identifier: String, source: Bool) {
        if source { settings.setSourceLanguageIdentifier(identifier) }
        else { settings.setTargetLanguageIdentifier(identifier) }
    }

    private func requestTranslationUsingSettings() {
        model.requestTranslation(targetLanguageIdentifier: settings.targetLanguageIdentifier,
                                 sourceLanguageIdentifier: settings.sourceLanguageIdentifier)
    }

    private var sourceLanguageName: String {
        if !settings.sourceLanguageIdentifier.isEmpty { return languageName(settings.sourceLanguageIdentifier) }
        if let detected = model.translationRequest?.sourceLanguage {
            return String(localized: "\(languageName(detected.minimalIdentifier)) (Auto)")
        }
        return String(localized: "Detect Automatically")
    }

    @ViewBuilder
    private var translationContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text("Translation").font(.caption).foregroundStyle(.secondary)
                    languagePair
                    Spacer(minLength: 4)
                    translationStatus
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Translation").font(.caption).foregroundStyle(.secondary); Spacer(); translationStatus }
                    languagePair
                }
            }
            .controlSize(.small)
            if !isSameTranslation {
                switch model.translationState {
                case .sentenceUnavailable:
                    Text("No sentence is available to translate.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .languageDownloadRequired:
                    Text("The selected languages need to be downloaded. Check the source and target languages before continuing.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Download Languages…") { model.retryTranslation(allowLanguageDownload: true) }
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.usesAppleTranslation ? String(localized: "Translating with Apple Translation…") : String(localized: "Translating…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .translated(let result):
                    Text(result.translatedText).lineSpacing(3).textSelection(.enabled)
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
    }

    private var isSameTranslation: Bool {
        guard case .translated(let result) = model.translationState else { return false }
        return result.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            == model.capture?.sentence?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var languagePair: some View {
        LookupLanguagePair(source: { languageMenu(source: true) }, target: { languageMenu(source: false) })
    }

    private var translationStatus: some View {
        HStack(spacing: 6) {
            if isSameTranslation { LookupSameTranslationBadge() }
            Text(settings.translation.provider.name).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    private func refreshTranslationConfiguration() {
        guard model.usesAppleTranslation, let request = model.translationRequest else {
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
            if let source = request.sourceLanguage {
                status = await LanguageAvailability().status(from: source, to: request.targetLanguage)
            } else {
                status = try await LanguageAvailability().status(for: request.text, to: request.targetLanguage)
            }
        } catch {
            return .failure(.unableToIdentifyLanguage)
        }
        guard status != .unsupported else {
            return .failure(.unsupportedLanguagePair)
        }
        if status == .supported, !request.allowsLanguageDownload { return .downloadRequired }
        do {
            // translate supplies the sample text for automatic source-language
            // detection and presents any required language download UI itself.
            try Task.checkCancellation()
            let response = try await session.translate(request.text)
            try Task.checkCancellation()
            return .success(
                TranslationResult(
                    requestID: request.id,
                    translatedText: response.targetText
                )
            )
        } catch is CancellationError {
            return .cancelled
        } catch TranslationError.unableToIdentifyLanguage {
            return .failure(.unableToIdentifyLanguage)
        } catch TranslationError.unsupportedSourceLanguage,
                TranslationError.unsupportedTargetLanguage,
                TranslationError.unsupportedLanguagePairing {
            return .failure(.unsupportedLanguagePair)
        } catch {
            return .failure(.internalFailure)
        }
    }

    private func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private var languageChoices: [(String, String)] {
        let selected = [settings.sourceLanguageIdentifier, settings.targetLanguageIdentifier].filter { !$0.isEmpty }
        return Set(languageIdentifiers + selected).map { ($0, languageName($0)) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    @ViewBuilder
    private var dictionaryContent: some View {
        switch model.dictionaryState {
        case .idle, .loading:
            pendingRow("Definition", detail: "Looking up in system dictionaries…")
        case .loaded(let entries):
            SystemDictionaryContentView(entries: entries, onLookup: model.selectWord)
                .id(model.activeDictionaryTerm)
        case .failed(let message):
            Label("Definition unavailable", systemImage: "exclamationmark.triangle").font(.headline)
            Text(message).foregroundStyle(.secondary)
            HStack {
                Button("Open Dictionary") { if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Dictionary") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) } }
                Button("Retry") { model.retryDictionaryLookup() }
            }
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
    case downloadRequired
}

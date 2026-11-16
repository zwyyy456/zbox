import AppKit
import Observation
import NaturalLanguage
import LookupPresentation
import SystemDictionary
import TranslationServices

nonisolated protocol SystemDictionaryReading: Sendable {
    func lookup(_ term: String) async throws -> [SystemDictionaryEntry]
}
extension SystemDictionaryReader: SystemDictionaryReading {}

enum TextLookupDictionaryState {
    case idle, loading
    case loaded([SystemDictionaryEntry])
    case failed(String)
}

nonisolated enum TextLookupTranslationFailure: Equatable, Sendable {
    case unableToIdentifyLanguage
    case unsupportedLanguagePair
    case cancelled
    case remoteFailure(String)
    case internalFailure

    var message: String {
        switch self {
        case .unableToIdentifyLanguage:
            String(localized: "The sentence language could not be identified.")
        case .unsupportedLanguagePair:
            String(localized: "Apple Translation does not support this language pair.")
        case .cancelled:
            String(localized: "Translation was cancelled.")
        case .remoteFailure(let message): message
        case .internalFailure:
            String(localized: "The sentence could not be translated.")
        }
    }
}

enum TextLookupTranslationState {
    case sentenceUnavailable
    case loading
    case languageDownloadRequired
    case translated(TranslationResult)
    case failed(TextLookupTranslationFailure)
}

@MainActor @Observable
final class TextLookupSessionModel {
    let windowState = LookupWindowState()
    var isPinned: Bool {
        get { windowState.isPinned }
        set { windowState.isPinned = newValue }
    }
    @ObservationIgnored private let dictionary: any SystemDictionaryReading
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var lookupID: UUID?
    @ObservationIgnored private var remoteTranslationTask: Task<Void, Never>?
    @ObservationIgnored var translationSettings: TextLookupTranslationSettings?
    private(set) var activeDictionaryTerm: String?
    private(set) var capture: TextLookupCapture?
    private(set) var isRecognizingWord = false
    private(set) var isLoadingContext = false
    private(set) var contextMessage: String?
    private(set) var captureError: TextCaptureError?
    private(set) var dictionaryState: TextLookupDictionaryState = .idle
    private var explicitSourceLanguage: String?
    private(set) var translationRequest: TranslationRequest?
    private(set) var translationState: TextLookupTranslationState = .sentenceUnavailable
    var integrationMessage: String?
    @ObservationIgnored var retryIntegration: (() -> Void)?
    var usesAppleTranslation: Bool { translationSettings?.provider == .apple || translationSettings == nil }

    init(dictionary: any SystemDictionaryReading = SystemDictionaryReader.shared) { self.dictionary = dictionary }

    func beginLookup(with capture: TextLookupCapture, targetLanguageIdentifier: String, sourceLanguageIdentifier: String = "") {
        clear()
        self.capture = capture
        startDictionaryLookup(term: capture.term)
        requestTranslation(targetLanguageIdentifier: targetLanguageIdentifier, sourceLanguageIdentifier: sourceLanguageIdentifier)
    }
    func beginOCR() { clear(); isRecognizingWord = true }
    func setContextStatus(id: UUID, loading: Bool, message: String?) {
        guard capture?.id == id, activeDictionaryTerm == capture?.term else { return }
        isLoadingContext = loading; contextMessage = message
    }
    func supplementContext(id: UUID, term: String, text: String?, isFragment: Bool, targetLanguageIdentifier: String, sourceLanguageIdentifier: String = "") {
        guard let current = capture, current.id == id, current.term == term,
              activeDictionaryTerm == term, current.needsContext else { return }
        isLoadingContext = false
        guard let text, !text.isEmpty else { return }
        capture = TextLookupCapture(id: current.id, term: current.term, sentence: text,
            sourceURL: current.sourceURL, anchorRect: current.anchorRect, isContextFragment: isFragment)
        contextMessage = nil
        requestTranslation(targetLanguageIdentifier: targetLanguageIdentifier, sourceLanguageIdentifier: sourceLanguageIdentifier)
    }
    func present(_ error: TextCaptureError) { clear(); captureError = error }
    func selectWord(_ term: String) {
        isLoadingContext = false; contextMessage = nil
        startDictionaryLookup(term: term)
    }
    func retryDictionaryLookup() { if let activeDictionaryTerm { startDictionaryLookup(term: activeDictionaryTerm) } }

    func requestTranslation(targetLanguageIdentifier: String, sourceLanguageIdentifier: String = "") {
        explicitSourceLanguage = sourceLanguageIdentifier.isEmpty ? nil : sourceLanguageIdentifier
        guard let sentence = capture?.sentence else {
            translationRequest = nil
            translationState = .sentenceUnavailable
            return
        }
        translationRequest = TranslationRequest(
            id: UUID(),
            text: sentence,
            targetLanguage: Locale.Language(identifier: targetLanguageIdentifier),
            sourceLanguage: sourceLanguageIdentifier.isEmpty
                ? NLLanguageRecognizer.dominantLanguage(for: sentence).map { Locale.Language(identifier: $0.rawValue) }
                : Locale.Language(identifier: sourceLanguageIdentifier)
        )
        translationState = .loading
        startRemoteTranslationIfNeeded()
    }

    func completeTranslation(_ result: TranslationResult) {
        guard translationRequest?.id == result.requestID else { return }
        translationState = .translated(result)
    }

    func failTranslation(_ failure: TextLookupTranslationFailure, requestID: UUID) {
        guard translationRequest?.id == requestID else { return }
        translationState = .failed(failure)
    }

    func requireLanguageDownload(requestID: UUID) {
        guard translationRequest?.id == requestID else { return }
        translationState = .languageDownloadRequired
    }

    func retryTranslation(allowLanguageDownload: Bool = false) {
        guard let request = translationRequest else { return }
        translationRequest = TranslationRequest(id: UUID(), text: request.text, targetLanguage: request.targetLanguage,
                                                sourceLanguage: request.sourceLanguage,
                                                allowsLanguageDownload: allowLanguageDownload)
        translationState = .loading
        startRemoteTranslationIfNeeded()
    }


    func clear() {
        lookupTask?.cancel(); lookupTask = nil; lookupID = nil
        remoteTranslationTask?.cancel(); remoteTranslationTask = nil
        activeDictionaryTerm = nil
        isRecognizingWord = false; isLoadingContext = false; contextMessage = nil
        capture = nil; captureError = nil; dictionaryState = .idle
        translationRequest = nil; translationState = .sentenceUnavailable
        integrationMessage = nil; retryIntegration = nil
    }

    private func startDictionaryLookup(term: String) {
        lookupTask?.cancel()
        let id = UUID(); lookupID = id; activeDictionaryTerm = term
        dictionaryState = .loading
        lookupTask = Task { [weak self, dictionary] in
            do {
                let entries = try await dictionary.lookup(term)
                try Task.checkCancellation()
                guard let self, self.lookupID == id else { return }
                dictionaryState = .loaded(entries)
            } catch is CancellationError { return }
            catch {
                guard let self, self.lookupID == id, !Task.isCancelled else { return }
                let message: String
                switch error {
                case SystemDictionaryError.noActiveDictionaries:
                    message = String(localized: "Enable and download dictionaries in the macOS Dictionary app, then restart Zento.")
                case SystemDictionaryError.noResult:
                    message = String(localized: "The enabled system dictionaries have no result for this word.")
                default: message = String(localized: "The system dictionary could not complete this lookup.")
                }
                dictionaryState = .failed(message)
            }
        }
    }

    private func startRemoteTranslationIfNeeded() {
        remoteTranslationTask?.cancel()
        guard let settings = translationSettings, settings.provider != .apple, let request = translationRequest else { return }
        let config = settings.snapshot
        let source = explicitSourceLanguage
        remoteTranslationTask = Task { [weak self] in
            do {
                let text = try await settings.translate(request.text, target: request.targetLanguage.minimalIdentifier, source: source, configuration: config)
                try Task.checkCancellation()
                self?.completeTranslation(TranslationResult(requestID: request.id, translatedText: text))
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                self?.failTranslation(.remoteFailure(TextLookupTranslationSettings.message(for: error)), requestID: request.id)
            }
        }
    }
}

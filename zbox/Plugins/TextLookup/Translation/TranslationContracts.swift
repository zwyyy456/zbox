import Foundation

nonisolated struct TranslationRequest: Equatable, Sendable {
    let id: UUID
    let text: String
    let sourceLanguage: Locale.Language?
    let targetLanguage: Locale.Language
}

nonisolated struct TranslationResult: Equatable, Sendable {
    let requestID: UUID
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
    let translatedText: String
}

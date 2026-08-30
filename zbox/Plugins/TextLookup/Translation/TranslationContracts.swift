import Foundation

nonisolated struct TranslationRequest: Sendable {
    let id: UUID
    let text: String
    let targetLanguage: Locale.Language
}

nonisolated struct TranslationResult: Sendable {
    let requestID: UUID
    let translatedText: String
}

import Foundation
import Translation

nonisolated struct TranslationRequest: Sendable {
    let id: UUID
    let text: String
    let targetLanguage: Locale.Language
    var sourceLanguage: Locale.Language? = nil
    var allowsLanguageDownload = false
}

nonisolated struct TranslationResult: Sendable {
    let requestID: UUID
    let translatedText: String
}

nonisolated enum TextLookupTranslationLanguages {
    @concurrent
    static func supportedIdentifiers() async -> [String] {
        let availability = LanguageAvailability()
        return await availability.supportedLanguages.map(\.minimalIdentifier)
    }
}

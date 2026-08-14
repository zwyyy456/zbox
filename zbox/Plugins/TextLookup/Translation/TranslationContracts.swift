import Foundation

nonisolated struct TranslationProviderID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let apple = Self(rawValue: "apple")
}

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

nonisolated protocol SentenceTranslationProviding: Sendable {
    var id: TranslationProviderID { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

nonisolated enum ThirdPartyTranslationKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case google
    case deepL
    case llm

    var id: String { rawValue }
    var label: String {
        switch self {
        case .google: "Google"
        case .deepL: "DeepL"
        case .llm: "LLM"
        }
    }
}

nonisolated struct ThirdPartyTranslationConfiguration: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: ThirdPartyTranslationKind
    let endpoint: String
    let modelIdentifier: String?
    let credentialID: String?
    let languageMappings: [String: String]
}

nonisolated protocol TranslationCredentialStoring: Sendable {
    func store(_ secret: Data, for id: String) async throws
    func load(for id: String) async throws -> Data?
    func remove(for id: String) async throws
}

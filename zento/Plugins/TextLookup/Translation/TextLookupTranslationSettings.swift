import Foundation
import Observation
import Security
import TranslationServices

nonisolated enum TextLookupTranslationProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, deepl, openAICompatible
    var id: String { rawValue }
    var name: String {
        switch self {
        case .apple: String(localized: "Apple Translation")
        case .deepl: "DeepL"
        case .openAICompatible: String(localized: "OpenAI-compatible API")
        }
    }
}
nonisolated struct TextLookupTranslationConfiguration: Codable, Equatable, Sendable {
    var provider = TextLookupTranslationProvider.apple
    var deepLEndpoint = "https://api-free.deepl.com/v2/translate"
    var openAIEndpoint = "https://api.openai.com/v1/chat/completions"
    var model = ""
}
nonisolated enum TextLookupRemoteTranslationError: Error { case missingCredential, invalidConfiguration, keychain(OSStatus) }

@MainActor @Observable
final class TextLookupTranslationSettings {
    private let defaults: UserDefaults
    private let credentials = TextLookupTranslationCredentials()
    private let deepL = DeepLTranslationService(transport: URLSessionTranslationHTTPTransport())
    private let openAI = OpenAICompatibleTranslationService(transport: URLSessionTranslationHTTPTransport())
    private(set) var snapshot: TextLookupTranslationConfiguration
    var errorMessage: String?
    var provider: TextLookupTranslationProvider { snapshot.provider }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: "plugin.text-lookup.translation").flatMap {
            try? JSONDecoder().decode(TextLookupTranslationConfiguration.self, from: $0)
        } ?? TextLookupTranslationConfiguration()
    }
    func save(_ configuration: TextLookupTranslationConfiguration, apiKey: String?) async -> Bool {
        do {
            if configuration.provider == .deepl {
                guard DeepLEndpoint.allCases.contains(where: { $0.rawValue == configuration.deepLEndpoint }) else { throw TextLookupRemoteTranslationError.invalidConfiguration }
            } else if configuration.provider == .openAICompatible {
                guard let url = URL(string: configuration.openAIEndpoint), url.scheme == "https", url.host != nil,
                      !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TextLookupRemoteTranslationError.invalidConfiguration }
            }
            if configuration.provider != .apple {
                if let apiKey, !apiKey.isEmpty { try await credentials.set(apiKey, for: configuration.provider) }
                guard try await credentials.get(configuration.provider)?.isEmpty == false else { throw TextLookupRemoteTranslationError.missingCredential }
            }
            defaults.set(try JSONEncoder().encode(configuration), forKey: "plugin.text-lookup.translation")
            snapshot = configuration; errorMessage = nil
            return true
        } catch { errorMessage = Self.message(for: error); return false }
    }
    func removeCredential(for provider: TextLookupTranslationProvider) async -> Bool {
        do {
            try await credentials.remove(provider)
            // Deleting a credential must not silently select another translation service.
            errorMessage = nil
            return true
        } catch { errorMessage = Self.message(for: error); return false }
    }
    func translate(_ text: String, target: String, source: String?, configuration: TextLookupTranslationConfiguration) async throws -> String {
        guard let key = try await credentials.get(configuration.provider), !key.isEmpty else { throw TextLookupRemoteTranslationError.missingCredential }
        switch configuration.provider {
        case .deepl:
            guard let endpoint = URL(string: configuration.deepLEndpoint) else { throw TextLookupRemoteTranslationError.invalidConfiguration }
            return try await deepL.translate(text: text, targetLanguageIdentifier: target, endpoint: endpoint, apiKey: key, sourceLanguageIdentifier: source).translatedText
        case .openAICompatible:
            guard let endpoint = URL(string: configuration.openAIEndpoint) else { throw TextLookupRemoteTranslationError.invalidConfiguration }
            return try await openAI.translate(text: text, targetLanguageIdentifier: target, endpoint: endpoint, model: configuration.model, apiKey: key, sourceLanguageIdentifier: source).translatedText
        case .apple: throw TextLookupRemoteTranslationError.invalidConfiguration
        }
    }
    static func message(for error: Error) -> String {
        switch error {
        case TextLookupRemoteTranslationError.missingCredential: String(localized: "Enter an API key in Text Lookup settings.")
        case TextLookupRemoteTranslationError.invalidConfiguration: String(localized: "Check the translation service address and model in Text Lookup settings.")
        case TextLookupRemoteTranslationError.keychain: String(localized: "The translation credential could not be accessed in Keychain.")
        case DeepLTranslationError.unauthorized, OpenAICompatibleTranslationError.unauthorized: String(localized: "The translation service rejected the API key.")
        case DeepLTranslationError.httpStatus(let status), OpenAICompatibleTranslationError.httpStatus(let status): String(localized: "The translation service returned HTTP \(status).")
        case is URLError: String(localized: "Could not connect to the selected translation service.")
        default: String(localized: "The selected translation service returned an invalid response.")
        }
    }
}

private actor TextLookupTranslationCredentials {
    private let service = "tech.hyperseek.zento.text-lookup.translation"
    private func query(_ provider: TextLookupTranslationProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }
    func get(_ provider: TextLookupTranslationProvider) throws -> String? {
        var request = query(provider)
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, let key = String(data: data, encoding: .utf8) else {
            throw TextLookupRemoteTranslationError.keychain(status)
        }
        return key
    }
    func set(_ key: String, for provider: TextLookupTranslationProvider) throws {
        let base = query(provider), value = [kSecValueData as String: Data(key.utf8)]
        let update = SecItemUpdate(base as CFDictionary, value as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw TextLookupRemoteTranslationError.keychain(update) }
        var request = base.merging(value) { _, new in new }
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else { throw TextLookupRemoteTranslationError.keychain(status) }
    }
    func remove(_ provider: TextLookupTranslationProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TextLookupRemoteTranslationError.keychain(status) }
    }
}

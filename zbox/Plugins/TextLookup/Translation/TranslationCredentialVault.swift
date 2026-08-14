import Foundation
import Security

nonisolated enum TranslationCredentialError: Error, Sendable {
    case keychain(OSStatus)
}

actor TranslationCredentialVault: TranslationCredentialStoring {
    private let service = "tech.hyperseek.zbox.text-lookup.translation"

    func store(_ secret: Data, for id: String) throws {
        let query = baseQuery(for: id)
        let update = [kSecValueData as String: secret] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = secret
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw TranslationCredentialError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw TranslationCredentialError.keychain(status)
        }
    }

    func load(for id: String) throws -> Data? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TranslationCredentialError.keychain(status) }
        return result as? Data
    }

    func remove(for id: String) throws {
        let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TranslationCredentialError.keychain(status)
        }
    }

    private func baseQuery(for id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
    }
}

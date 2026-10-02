import Foundation
import Security

nonisolated enum ScreenshotCredentialStore {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "zbox") + ".screenshot.hosting" }
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    static func load(_ id: UUID) throws -> ScreenshotHostCredentials {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return ScreenshotHostCredentials() }
        guard status == errSecSuccess, let data = result as? Data,
              let credentials = try? JSONDecoder().decode(ScreenshotHostCredentials.self, from: data) else {
            throw ScreenshotUploadError.keychain
        }
        return credentials
    }

    static func save(_ credentials: ScreenshotHostCredentials, for id: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = query(id)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ScreenshotUploadError.keychain }
        } else if status != errSecSuccess { throw ScreenshotUploadError.keychain }
    }

    static func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ScreenshotUploadError.keychain }
    }
}

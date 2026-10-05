import Foundation
import Security

actor ExtensionDataStore {
    let root: URL
    let id: String
    init(root: URL, id: String) { self.root = root; self.id = id }

    func settings() throws -> [String: String] {
        let url = root.appending(path: "settings.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: read(url))
    }

    func saveSettings(_ settings: [String: String]) throws { try write(JSONEncoder().encode(settings), to: root.appending(path: "settings.json")) }

    func storage(_ key: String, value: ExtensionValue? = nil) throws -> ExtensionValue {
        guard !key.isEmpty, key.utf8.count <= 128 else { throw ExtensionFailure("Invalid storage key.") }
        let url = root.appending(path: "storage.json")
        var values: [String: ExtensionValue] = [:]
        if FileManager.default.fileExists(atPath: url.path) { values = try JSONDecoder().decode([String: ExtensionValue].self, from: read(url)) }
        if let value {
            values[key] = value
            try write(JSONEncoder().encode(values), to: url)
        }
        return values[key] ?? .null
    }

    func credential(_ key: String, value: String? = nil, delete: Bool = false) throws -> String? {
        guard !key.isEmpty, key.utf8.count <= 128 else { throw ExtensionFailure("Invalid credential key.") }
        try Task.checkCancellation()
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "tech.hyperseek.zbox.extensions.\(id)", kSecAttrAccount as String: key]
        let status: OSStatus
        if delete { status = SecItemDelete(query as CFDictionary) }
        else if let value {
            guard value.utf8.count <= 1_048_576 else { throw ExtensionFailure("Credential exceeds 1 MiB.") }
            let data = Data(value.utf8)
            let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if update == errSecItemNotFound {
                query[kSecValueData as String] = data
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(query as CFDictionary, nil)
            } else { status = update }
        } else {
            query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data { return String(data: data, encoding: .utf8) }
        }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ExtensionFailure("Keychain operation failed (\(status)).") }
        return nil
    }

    func deleteAll() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "tech.hyperseek.zbox.extensions.\(id)"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ExtensionFailure("Could not remove extension credentials (\(status)).") }
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    private func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw ExtensionFailure("Extension data exceeds 1 MiB.") }
        return data
    }

    private func write(_ data: Data, to url: URL) throws {
        guard data.count <= 1_048_576 else { throw ExtensionFailure("Extension data exceeds 1 MiB.") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
    }
}

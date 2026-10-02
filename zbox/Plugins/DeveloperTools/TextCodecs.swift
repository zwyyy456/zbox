import Foundation

nonisolated struct DeveloperToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

nonisolated enum URLCodec {
    static func encode(_ input: String) -> String {
        input.addingPercentEncoding(withAllowedCharacters:
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))!
    }

    static func decode(_ input: String) throws -> String {
        guard let result = input.removingPercentEncoding else {
            throw DeveloperToolError(message: String(localized: "Invalid percent encoding or UTF-8 text."))
        }
        return result
    }
}

nonisolated enum Base64Codec {
    static func encode(_ input: String, urlSafe: Bool) -> String {
        let encoded = Data(input.utf8).base64EncodedString()
        return urlSafe ? encoded.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") : encoded
    }

    static func decode(_ input: String, urlSafe: Bool) throws -> String {
        let compact = String(String.UnicodeScalarView(input.unicodeScalars.filter { ![32, 9, 13, 10].contains($0.value) }))
        var standard = compact
        if urlSafe {
            guard !compact.contains("+"), !compact.contains("/") else { throw invalidEncoding }
            standard = compact.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            if !standard.contains("=") {
                standard += String(repeating: "=", count: (4 - standard.utf8.count % 4) % 4)
            }
        }
        guard let data = Data(base64Encoded: standard), data.base64EncodedString() == standard else {
            throw invalidEncoding
        }
        guard let result = String(data: data, encoding: .utf8) else {
            throw DeveloperToolError(message: String(localized: "The decoded result is not UTF-8 text."))
        }
        return result
    }

    private static var invalidEncoding: DeveloperToolError {
        DeveloperToolError(message: String(localized: "Invalid Base64 characters, length, or padding."))
    }
}

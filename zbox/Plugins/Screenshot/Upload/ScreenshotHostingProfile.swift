import Foundation

nonisolated enum ScreenshotHost: String, Codable, CaseIterable, Identifiable {
    case r2, s3, oss, cos, qiniu, upyun, smms
    var id: String { rawValue }
    var title: String {
        switch self {
        case .r2: "Cloudflare R2"
        case .s3: "Amazon S3"
        case .oss: String(localized: "Aliyun OSS")
        case .cos: String(localized: "Tencent COS")
        case .qiniu: String(localized: "Qiniu")
        case .upyun: String(localized: "Upyun")
        case .smms: "SM.MS / S.EE"
        }
    }
    var needsRegion: Bool { [.s3, .oss, .cos].contains(self) }
    var needsEndpoint: Bool { self == .r2 || self == .qiniu }
}

nonisolated struct ScreenshotHostingProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var provider = ScreenshotHost.r2
    var bucket = ""
    var region = ""
    var endpoint = ""
    var publicBaseURL = ""
    var prefix = "screenshots"

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenshotUploadError.configuration(String(localized: "Enter a name for this image host."))
        }
        guard provider != .smms else { return }
        let componentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard !bucket.isEmpty, bucket.unicodeScalars.allSatisfy(componentCharacters.contains),
              !bucket.hasPrefix("."), !bucket.hasSuffix(".") else {
            throw ScreenshotUploadError.configuration(String(localized: "Enter a valid bucket or service name."))
        }
        if provider.needsRegion {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
            guard !region.isEmpty, region.unicodeScalars.allSatisfy(allowed.contains) else {
                throw ScreenshotUploadError.configuration(String(localized: "Enter the bucket region, such as us-east-1 or cn-hangzhou."))
            }
        }
        if provider.needsEndpoint { _ = try Self.httpsURL(endpoint, rootOnly: true) }
        _ = try Self.httpsURL(publicBaseURL)
        guard !prefix.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !prefix.contains("\\"), !prefix.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw ScreenshotUploadError.configuration(String(localized: "The object path prefix contains invalid characters."))
        }
    }

    func objectKey(filename: String) -> String {
        let directory = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return directory.isEmpty ? filename : "\(directory)/\(filename)"
    }

    static func httpsURL(_ value: String, rootOnly: Bool = false) throws -> URL {
        guard let components = URLComponents(string: value), components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !rootOnly || components.path.isEmpty || components.path == "/",
              let url = components.url else {
            throw ScreenshotUploadError.configuration(String(localized: "Use an HTTPS URL without credentials, query parameters or fragments. Upload endpoints must not include a bucket or path."))
        }
        return url
    }

    static func appending(_ key: String, to base: URL) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = (basePath.isEmpty ? "" : "/" + basePath) + "/" + ScreenshotSigning.encodePath(key)
        return components.url!
    }
}

nonisolated struct ScreenshotHostCredentials: Codable, Sendable {
    var accessKey = ""
    var secretKey = ""
    var sessionToken = ""

    func validate(for host: ScreenshotHost) throws {
        guard !secretKey.isEmpty, host == .smms || !accessKey.isEmpty,
              ![accessKey, secretKey, sessionToken].contains(where: { $0.contains("\r") || $0.contains("\n") }) else {
            throw ScreenshotUploadError.credentials
        }
    }
}

nonisolated enum ScreenshotUploadError: LocalizedError, Equatable {
    case configuration(String), credentials, keychain, invalidResponse, serviceRejected, rejected(Int), network
    var errorDescription: String? {
        switch self {
        case .configuration(let message): message
        case .credentials: String(localized: "Enter the credentials required by this image host.")
        case .keychain: String(localized: "Image host credentials could not be read or saved in Keychain.")
        case .invalidResponse: String(localized: "The image host returned an invalid upload result.")
        case .serviceRejected: String(localized: "The image host rejected the upload. Check your API key, account limits and file size.")
        case .rejected(let code): String(localized: "Upload failed (HTTP \(code)). Check the host settings, permissions and account limits.")
        case .network: String(localized: "Upload failed. Check your connection and image host settings, then retry.")
        }
    }
}

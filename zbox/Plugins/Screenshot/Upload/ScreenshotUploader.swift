import Foundation

nonisolated struct ScreenshotUploadRequest: Sendable {
    var request: URLRequest
    let body: Data
    let objectKey: String
    let publicURL: URL?
}

nonisolated enum ScreenshotUploader {
    static func request(profile: ScreenshotHostingProfile, credentials: ScreenshotHostCredentials,
                        image: Data, format: ScreenshotFormat, filename: String, date: Date = .now) throws -> ScreenshotUploadRequest {
        try profile.validate()
        try credentials.validate(for: profile.provider)
        let key = profile.objectKey(filename: filename)
        let endpoint: URL
        switch profile.provider {
        case .r2:
            endpoint = ScreenshotHostingProfile.appending(profile.bucket + "/" + key, to: try ScreenshotHostingProfile.httpsURL(profile.endpoint, rootOnly: true))
        case .s3:
            let suffix = profile.region.hasPrefix("cn-") ? "amazonaws.com.cn" : "amazonaws.com"
            endpoint = ScreenshotHostingProfile.appending(profile.bucket + "/" + key, to: URL(string: "https://s3.\(profile.region).\(suffix)")!)
        case .oss:
            endpoint = ScreenshotHostingProfile.appending(key, to: URL(string: "https://\(profile.bucket).oss-\(profile.region).aliyuncs.com")!)
        case .cos:
            endpoint = ScreenshotHostingProfile.appending(key, to: URL(string: "https://\(profile.bucket).cos.\(profile.region).myqcloud.com")!)
        case .qiniu: endpoint = try ScreenshotHostingProfile.httpsURL(profile.endpoint, rootOnly: true)
        case .upyun: endpoint = ScreenshotHostingProfile.appending(profile.bucket + "/" + key, to: URL(string: "https://v0.api.upyun.com")!)
        case .smms: endpoint = URL(string: "https://s.ee/api/v1/file/upload")!
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        let mime = format == .png ? "image/png" : "image/jpeg"
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        var body = image
        switch profile.provider {
        case .r2, .s3:
            ScreenshotSigning.signS3(&request, body: body, credentials: credentials,
                                     region: profile.provider == .r2 ? "auto" : profile.region, date: date)
        case .oss:
            ScreenshotSigning.signOSS(&request, credentials: credentials, bucket: profile.bucket, key: key, region: profile.region, date: date)
        case .cos: ScreenshotSigning.signCOS(&request, credentials: credentials, objectKey: key, date: date)
        case .upyun: ScreenshotSigning.signUpyun(&request, body: body, credentials: credentials, date: date)
        case .qiniu, .smms:
            request.httpMethod = "POST"
            let boundary = "zbox-" + UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var fields: [(String, String)] = []
            if profile.provider == .qiniu {
                fields = [("key", key), ("token", try ScreenshotSigning.qiniuToken(credentials: credentials, bucket: profile.bucket, key: key, date: date))]
            } else {
                request.setValue(credentials.secretKey, forHTTPHeaderField: "Authorization")
            }
            body = multipart(image: image, filename: filename, mime: mime, fields: fields, boundary: boundary)
        }
        let publicURL = profile.provider == .smms ? nil
            : ScreenshotHostingProfile.appending(key, to: try ScreenshotHostingProfile.httpsURL(profile.publicBaseURL))
        return ScreenshotUploadRequest(request: request, body: body, objectKey: key, publicURL: publicURL)
    }

    private static func multipart(image: Data, filename: String, mime: String, fields: [(String, String)], boundary: String) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8))
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    static func result(data: Data, statusCode: Int, profile: ScreenshotHostingProfile, request: ScreenshotUploadRequest) throws -> URL {
        guard (200..<300).contains(statusCode) else { throw ScreenshotUploadError.rejected(statusCode) }
        if profile.provider == .smms {
            struct Reply: Decodable { let code: Int; let data: Item? }
            struct Item: Decodable { let url: String }
            guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw ScreenshotUploadError.invalidResponse }
            guard reply.code == 0 else { throw ScreenshotUploadError.serviceRejected }
            guard let raw = reply.data?.url, let url = URL(string: raw), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil else { throw ScreenshotUploadError.invalidResponse }
            return url
        }
        if profile.provider == .qiniu {
            struct Reply: Decodable { let key: String }
            guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.key == request.objectKey else {
                throw ScreenshotUploadError.invalidResponse
            }
        }
        guard let url = request.publicURL else { throw ScreenshotUploadError.invalidResponse }
        return url
    }

    @concurrent
    static func upload(profile: ScreenshotHostingProfile, credentials: ScreenshotHostCredentials,
                       image: Data, format: ScreenshotFormat, filename: String,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let prepared = try request(profile: profile, credentials: credentials, image: image, format: format, filename: filename)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.httpShouldSetCookies = false
        let delegate = ScreenshotUploadDelegate(progress: progress)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.upload(for: prepared.request, from: prepared.body)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw ScreenshotUploadError.invalidResponse }
            return try result(data: data, statusCode: response.statusCode, profile: profile, request: prepared)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ScreenshotUploadError { throw error }
        catch {
            try Task.checkCancellation()
            throw ScreenshotUploadError.network
        }
    }
}

nonisolated private final class ScreenshotUploadDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { progress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Signed requests and upload tokens must never be forwarded to a redirect target.
        completionHandler(nil)
    }
}

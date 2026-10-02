import CryptoKit
import Foundation

/// Only the request signing used by the built-in image hosts; no general cloud SDK.
nonisolated enum ScreenshotSigning {
    static func hex<S: Sequence>(_ data: S) -> String where S.Element == UInt8 {
        data.map { String(format: "%02x", $0) }.joined()
    }
    static func sha256(_ data: Data) -> String { hex(SHA256.hash(data: data)) }
    static func hmac256(_ key: Data, _ value: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key)))
    }
    static func hmac1(_ key: String, _ value: String) -> Data {
        Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: Data(key.utf8))))
    }
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"))!
    }
    static func encodePath(_ value: String) -> String { value.components(separatedBy: "/").map(encode).joined(separator: "/") }
    static func timestamp(_ date: Date, format: String = "yyyyMMdd'T'HHmmss'Z'") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }

    static func signS3(_ request: inout URLRequest, body: Data, credentials: ScreenshotHostCredentials, region: String, date: Date) {
        let stamp = timestamp(date)
        let day = String(stamp.prefix(8))
        request.setValue(request.url!.host! + (request.url!.port.map { ":\($0)" } ?? ""), forHTTPHeaderField: "Host")
        request.setValue(stamp, forHTTPHeaderField: "x-amz-date")
        let hash = sha256(body)
        request.setValue(hash, forHTTPHeaderField: "x-amz-content-sha256")
        if !credentials.sessionToken.isEmpty { request.setValue(credentials.sessionToken, forHTTPHeaderField: "x-amz-security-token") }
        let headers = canonicalHeaders(request)
        let names = headers.map(\.0).joined(separator: ";")
        let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.percentEncodedPath
        let canonical = "\(request.httpMethod!)\n\(path)\n\n\(headers.map { "\($0):\($1)\n" }.joined())\n\(names)\n\(hash)"
        let scope = "\(day)/\(region)/s3/aws4_request"
        let toSign = "AWS4-HMAC-SHA256\n\(stamp)\n\(scope)\n\(sha256(Data(canonical.utf8)))"
        var key = hmac256(Data(("AWS4" + credentials.secretKey).utf8), day)
        for value in [region, "s3", "aws4_request"] { key = hmac256(key, value) }
        request.setValue("AWS4-HMAC-SHA256 Credential=\(credentials.accessKey)/\(scope),SignedHeaders=\(names),Signature=\(hex(hmac256(key, toSign)))", forHTTPHeaderField: "Authorization")
    }

    static func signOSS(_ request: inout URLRequest, credentials: ScreenshotHostCredentials, bucket: String, key objectKey: String, region: String, date: Date) {
        let stamp = timestamp(date)
        let day = String(stamp.prefix(8))
        request.setValue(stamp, forHTTPHeaderField: "x-oss-date")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-oss-content-sha256")
        if !credentials.sessionToken.isEmpty { request.setValue(credentials.sessionToken, forHTTPHeaderField: "x-oss-security-token") }
        let headers = canonicalHeaders(request).filter { $0.0.hasPrefix("x-oss-") || ["content-type", "content-md5"].contains($0.0) }
        let canonical = "PUT\n/\(encodePath(bucket + "/" + objectKey))\n\n\(headers.map { "\($0):\($1)\n" }.joined())\n\nUNSIGNED-PAYLOAD"
        let scope = "\(day)/\(region)/oss/aliyun_v4_request"
        let toSign = "OSS4-HMAC-SHA256\n\(stamp)\n\(scope)\n\(sha256(Data(canonical.utf8)))"
        var key = hmac256(Data(("aliyun_v4" + credentials.secretKey).utf8), day)
        for value in [region, "oss", "aliyun_v4_request"] { key = hmac256(key, value) }
        request.setValue("OSS4-HMAC-SHA256 Credential=\(credentials.accessKey)/\(scope),Signature=\(hex(hmac256(key, toSign)))", forHTTPHeaderField: "Authorization")
    }

    static func signCOS(_ request: inout URLRequest, credentials: ScreenshotHostCredentials, objectKey: String, date: Date) {
        let start = Int(date.timeIntervalSince1970)
        let time = "\(start);\(start + 900)"
        request.setValue(request.url!.host! + (request.url!.port.map { ":\($0)" } ?? ""), forHTTPHeaderField: "Host")
        if !credentials.sessionToken.isEmpty { request.setValue(credentials.sessionToken, forHTTPHeaderField: "x-cos-security-token") }
        let headers = canonicalHeaders(request)
        let httpString = "put\n/\(objectKey)\n\n\(headers.map { "\(encode($0))=\(encode($1))" }.joined(separator: "&"))\n"
        let toSign = "sha1\n\(time)\n\(hex(Insecure.SHA1.hash(data: Data(httpString.utf8))))\n"
        let signKey = hex(hmac1(credentials.secretKey, time))
        let signature = hex(hmac1(signKey, toSign))
        request.setValue("q-sign-algorithm=sha1&q-ak=\(encode(credentials.accessKey))&q-sign-time=\(time)&q-key-time=\(time)&q-header-list=\(headers.map(\.0).joined(separator: ";"))&q-url-param-list=&q-signature=\(signature)", forHTTPHeaderField: "Authorization")
    }

    static func signUpyun(_ request: inout URLRequest, body: Data, credentials: ScreenshotHostCredentials, date: Date) {
        let stamp = timestamp(date, format: "EEE, dd MMM yyyy HH:mm:ss 'GMT'")
        let md5 = hex(Insecure.MD5.hash(data: body))
        request.setValue(stamp, forHTTPHeaderField: "Date")
        request.setValue(md5, forHTTPHeaderField: "Content-MD5")
        request.setValue("true", forHTTPHeaderField: "mkdir")
        let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.percentEncodedPath
        let password = hex(Insecure.MD5.hash(data: Data(credentials.secretKey.utf8)))
        let signature = hmac1(password, "PUT&\(path)&\(stamp)&\(md5)").base64EncodedString()
        request.setValue("UPYUN \(credentials.accessKey):\(signature)", forHTTPHeaderField: "Authorization")
    }

    static func qiniuToken(credentials: ScreenshotHostCredentials, bucket: String, key: String, date: Date) throws -> String {
        let policy: [String: Any] = ["scope": "\(bucket):\(key)", "deadline": Int(date.timeIntervalSince1970) + 3600]
        let encoded = base64URL(try JSONSerialization.data(withJSONObject: policy, options: [.sortedKeys, .withoutEscapingSlashes]))
        return credentials.accessKey + ":" + base64URL(hmac1(credentials.secretKey, encoded)) + ":" + encoded
    }

    private static func canonicalHeaders(_ request: URLRequest) -> [(String, String)] {
        (request.allHTTPHeaderFields ?? [:]).map {
            ($0.key.lowercased(), $0.value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
        }.sorted { $0.0 < $1.0 }
    }
}

import Foundation
import Testing
@testable import zbox

struct ScreenshotUploadTests {
    private let date = Date(timeIntervalSince1970: 1_744_353_684)
    private let credentials = ScreenshotHostCredentials(accessKey: "test-key", secretKey: "test-secret")

    @Test func matchesSignatureFixtures() throws {
        // AWS's published SigV4 GET example; these are public example credentials.
        var s3 = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
        s3.httpMethod = "GET"
        s3.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        ScreenshotSigning.signS3(&s3, body: Data(), credentials: ScreenshotHostCredentials(
            accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"),
            region: "us-east-1", date: Date(timeIntervalSince1970: 1_369_353_600))
        #expect(s3.value(forHTTPHeaderField: "Authorization")?.hasSuffix("Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41") == true)

        // OSS/COS fixtures independently calculated from their documented canonical requests.
        var oss = URLRequest(url: URL(string: "https://bucket.oss-cn-hangzhou.aliyuncs.com/shots/hello%20%E4%B8%AD.png")!)
        oss.httpMethod = "PUT"
        oss.setValue("image/png", forHTTPHeaderField: "Content-Type")
        ScreenshotSigning.signOSS(&oss, credentials: credentials, bucket: "bucket", key: "shots/hello 中.png", region: "cn-hangzhou", date: date)
        #expect(oss.value(forHTTPHeaderField: "Authorization")?.hasSuffix("Signature=d296fbd1bb7addc05c6ca4ff02e694e8409690cce8f323aba01f28bb6e93945b") == true)
        var cos = URLRequest(url: URL(string: "https://bucket-123.cos.ap-guangzhou.myqcloud.com/shots/hello%20%E4%B8%AD.png")!)
        cos.httpMethod = "PUT"
        cos.setValue("image/png", forHTTPHeaderField: "Content-Type")
        ScreenshotSigning.signCOS(&cos, credentials: credentials, objectKey: "shots/hello 中.png", date: date)
        #expect(cos.value(forHTTPHeaderField: "Authorization")?.hasSuffix("q-signature=171ef177f5f416b82f2a19eeca2c8515bb0a7957") == true)

        // Upyun's published upload example.
        var upyun = URLRequest(url: URL(string: "https://v0.api.upyun.com/upyun-temp/demo.jpg")!)
        upyun.httpMethod = "PUT"
        let upyunDate = try #require(ISO8601DateFormatter().date(from: "2016-11-09T14:26:58Z"))
        ScreenshotSigning.signUpyun(&upyun, body: Data("abcdefg".utf8),
            credentials: ScreenshotHostCredentials(accessKey: "operator123", secretKey: "password123"), date: upyunDate)
        #expect(upyun.value(forHTTPHeaderField: "Authorization") == "UPYUN operator123:YUaAZX+WNAcJdNGHS5SBlITME5A=")
        #expect(try ScreenshotSigning.qiniuToken(credentials: credentials, bucket: "bucket", key: "demo.png", date: date)
            == "test-key:MquowXjAOcjdVTJw5HEV6zJzlIY=:eyJkZWFkbGluZSI6MTc0NDM1NzI4NCwic2NvcGUiOiJidWNrZXQ6ZGVtby5wbmcifQ==")
    }

    @Test(arguments: ScreenshotHost.allCases)
    func buildsRequestsAndRejectsFailedResponses(provider: ScreenshotHost) throws {
        let profile = ScreenshotHostingProfile(name: "Fixture", provider: provider, bucket: "bucket", region: "cn-hangzhou",
            endpoint: "https://upload.example.com", publicBaseURL: "https://images.example.com/base", prefix: "截图 & notes")
        let plan = try ScreenshotUploader.request(profile: profile, credentials: credentials,
            image: Data([0, 1, 2, 255]), format: .png, filename: "sample.png", date: date)
        #expect(plan.request.url?.scheme == "https")
        #expect(plan.request.httpMethod == ([.qiniu, .smms].contains(provider) ? "POST" : "PUT"))
        #expect(!plan.body.isEmpty)
        if provider == .smms {
            #expect(plan.request.url?.absoluteString == "https://s.ee/api/v1/file/upload")
            #expect(plan.request.value(forHTTPHeaderField: "Authorization") == "test-secret")
            let data = Data(#"{"code":0,"data":{"url":"https://i.s.ee/test.png"}}"#.utf8)
            #expect(try ScreenshotUploader.result(data: data, statusCode: 200, profile: profile, request: plan).host == "i.s.ee")
            #expect(throws: ScreenshotUploadError.invalidResponse) {
                _ = try ScreenshotUploader.result(data: Data(#"{"code":400,"message":"private response"}"#.utf8), statusCode: 200, profile: profile, request: plan)
            }
        } else {
            let data = try JSONSerialization.data(withJSONObject: ["key": plan.objectKey])
            let url = try ScreenshotUploader.result(data: data, statusCode: 200, profile: profile, request: plan)
            #expect(url.absoluteString == "https://images.example.com/base/%E6%88%AA%E5%9B%BE%20%26%20notes/sample.png")
            if provider == .r2 { #expect(plan.request.value(forHTTPHeaderField: "Authorization")?.contains("/auto/s3/") == true) }
            if provider == .qiniu {
                let body = String(decoding: plan.body, as: UTF8.self)
                #expect(body.contains("name=\"key\"\r\n\r\n截图 & notes/sample.png"))
                #expect(body.contains("name=\"token\""))
                #expect(body.contains("name=\"file\"; filename=\"sample.png\""))
                #expect(throws: ScreenshotUploadError.invalidResponse) {
                    _ = try ScreenshotUploader.result(data: Data(#"{"key":"wrong.png"}"#.utf8), statusCode: 200, profile: profile, request: plan)
                }
            }
        }
        #expect(throws: ScreenshotUploadError.rejected(403)) {
            _ = try ScreenshotUploader.result(data: Data("private error body".utf8), statusCode: 403, profile: profile, request: plan)
        }
    }

    @Test func rejectsUnsafeConfigurationAndResponseURLs() throws {
        for raw in ["http://example.com", "https://user:secret@example.com", "https://example.com?token=secret", "https://example.com/bucket"] {
            #expect(throws: ScreenshotUploadError.self) { _ = try ScreenshotHostingProfile.httpsURL(raw, rootOnly: true) }
        }
        let profile = ScreenshotHostingProfile(name: "Fixture", provider: .smms)
        let plan = try ScreenshotUploader.request(profile: profile, credentials: credentials,
            image: Data([0]), format: .png, filename: "fixture.png")
        #expect(throws: ScreenshotUploadError.invalidResponse) {
            _ = try ScreenshotUploader.result(data: Data(#"{"code":0,"data":{"url":"file:///private/test.png"}}"#.utf8), statusCode: 200, profile: profile, request: plan)
        }
    }
}

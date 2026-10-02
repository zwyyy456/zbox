import Foundation
import Testing
@testable import zbox

struct DeveloperTextCodecTests {
    @Test func urlComponentsPreserveTheirMeaning() throws {
        let source = "你好 hello+a/b?x=1&y=%20"
        let encoded = URLCodec.encode(source)
        #expect(encoded == "%E4%BD%A0%E5%A5%BD%20hello%2Ba%2Fb%3Fx%3D1%26y%3D%2520")
        #expect(try URLCodec.decode(encoded) == source)
        #expect(try URLCodec.decode("+%2520") == "+%20")
        for invalid in ["%", "%2", "%GG", "%FF", "%E4%BD"] {
            #expect(throws: DeveloperToolError.self) { try URLCodec.decode(invalid) }
        }
    }

    @Test func base64AcceptsOnlyTheSelectedAlphabetAndValidPadding() throws {
        for source in ["", "f", "fo", "foo", "你好🙂", "\u{FFFF}"] {
            for urlSafe in [false, true] {
                #expect(try Base64Codec.decode(Base64Codec.encode(source, urlSafe: urlSafe), urlSafe: urlSafe) == source)
            }
        }
        #expect(try Base64Codec.decode(" Z g = =\r\n\t", urlSafe: false) == "f")
        #expect(try Base64Codec.decode("Zg", urlSafe: true) == "f")
        #expect(try Base64Codec.decode("Zg==", urlSafe: true) == "f")
        for invalid in ["Zg", "Zg=", "Zh==", "Zg===", "Z=g=", "Zg==!", "Zg==\u{00a0}", "/w==", "77-_", "A"] {
            #expect(throws: DeveloperToolError.self) { try Base64Codec.decode(invalid, urlSafe: false) }
        }
        for invalid in ["77+/", "A", "Zh", "Zg=", "Zg==!"] {
            #expect(throws: DeveloperToolError.self) { try Base64Codec.decode(invalid, urlSafe: true) }
        }
    }
}

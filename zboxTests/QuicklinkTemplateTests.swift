import Foundation
import Testing
@testable import zbox

struct QuicklinkTemplateTests {
    @Test func encodesAValueWithoutChangingURLStructure() throws {
        let template = try QuicklinkTemplate("https://example.com/search/{query}?q={query}&fixed=yes#section")
        let query = "中文 &/#?+%="
        let url = try template.destination(query: query)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.queryItems == [URLQueryItem(name: "q", value: query), URLQueryItem(name: "fixed", value: "yes")])
        #expect(parts.percentEncodedPath.contains("%2F"))
        #expect(parts.fragment == "section")
    }

    @Test(arguments: ["https://{query}.com/", "https://example.com/?{query}=x", "https://example.com/#{query}", "https://{query}@example.com/", "custom://example.com/{query}", "https://example.com/{other}"])
    func rejectsStructuralPlaceholders(_ source: String) {
        #expect(throws: (any Error).self) { try QuicklinkTemplate(source) }
    }
}

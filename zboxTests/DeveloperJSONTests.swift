import Foundation
import Testing
@testable import zbox

struct DeveloperJSONTests {
    @Test func formattingPreservesTokensAndOrder() throws {
        let source = #" { "id":9007199254740993, "id":1.2300,"exp":1e9999,"s":"\u4f60\/\n", "a": [true, null,{}] } "#
        let compact = #"{"id":9007199254740993,"id":1.2300,"exp":1e9999,"s":"\u4f60\/\n","a":[true,null,{}]}"#
        #expect(try JSONFormatter.process(source, operation: .compact) == compact)
        let formatted = try JSONFormatter.process(source, operation: .format, indentation: 4)
        #expect(formatted.hasPrefix("{\n    \"id\": 9007199254740993,"))
        #expect(try JSONFormatter.process(formatted, operation: .compact) == compact)
        #expect(try JSONFormatter.process(formatted, operation: .validate) == "")
        for scalar in ["0", "-0.1E+2", "true", "false", "null", #""文字🙂""#] {
            #expect(try JSONFormatter.process(scalar, operation: .compact) == scalar)
        }
    }

    @Test func rejectsInvalidGrammarAndReportsUnicodeLocation() throws {
        for source in ["", "[1,]", #"{"a":1,}"#, "01", "+1", "1.", "1e", "-.1", "NaN", "true false", "/*x*/null", #""\x""#, #""\u123""#, "\"line\nfeed\"", "[}", #"{"a" 1}"#] {
            #expect(throws: JSONSyntaxError.self) { try JSONFormatter.process(source, operation: .validate) }
        }
        let source = "{\r\n\"🙂\": 1,\r\n}"
        do {
            _ = try JSONFormatter.process(source, operation: .format)
            Issue.record("Expected a trailing comma error")
        } catch let error as JSONSyntaxError {
            #expect(error.line == 3)
            #expect(error.column == 1)
            #expect(error.utf16Offset == source.utf16.count - 1)
        }
        let nested = String(repeating: "[", count: 256) + "0" + String(repeating: "]", count: 256)
        #expect(try JSONFormatter.process(nested, operation: .validate) == "")
        #expect(throws: JSONSyntaxError.self) { try JSONFormatter.process("[" + nested + "]", operation: .validate) }
    }
    @Test func boundsExpansionAndHonorsCancellation() async throws {
        let wide = String(repeating: "[", count: 200) + Array(repeating: "0", count: 12_000).joined(separator: ",")
            + String(repeating: "]", count: 200)
        #expect(throws: DeveloperToolError.self) { try JSONFormatter.process(wide, operation: .format, indentation: 4) }
        #expect(throws: DeveloperToolError.self) {
            try JSONFormatter.process(String(repeating: " ", count: 1_048_577), operation: .validate)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try JSONFormatter.process("{}", operation: .format)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

}

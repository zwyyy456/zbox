import Foundation
import Testing
@testable import SystemDictionary
struct SystemDictionaryResourceTests {
    @Test func latinQueriesDoNotReturnChinesePhoneticMatches() {
        #expect(SystemDictionaryHeadword.matches("run", query: "run"))
        #expect(SystemDictionaryHeadword.matches("run", query: "running"))
        #expect(SystemDictionaryHeadword.matches("child", query: "children"))
        #expect(SystemDictionaryHeadword.matches("École", query: "ecole"))
        #expect(!SystemDictionaryHeadword.matches("润  rùn", query: "run"))
        #expect(!SystemDictionaryHeadword.matches("run-", query: "run"))
        #expect(SystemDictionaryHeadword.matches("润  rùn", query: "润"))
    }
    @Test func resourcesCannotEscapeOwningDictionary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: contents.appendingPathComponent("Resources/style.css"))
        try Data([2]).write(to: root.appendingPathComponent("outside.css"))
        #expect(SystemDictionaryResource.resolve("style.css", contentsURL: contents) != nil)
        #expect(SystemDictionaryResource.resolve("../outside.css", contentsURL: contents) == nil)
        #expect(SystemDictionaryResource.resolve(root.appendingPathComponent("outside.css").path, contentsURL: contents) == nil)
    }
}

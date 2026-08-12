import Testing
@testable import zbox

struct SearchEngineTests {
    private let engine = SearchEngine()

    @Test
    func normalizesCaseAndDiacritics() {
        let commands = [descriptor("cafe", title: "Café")]

        let results = engine.search(query: "CAFE", in: commands, limit: 8)

        #expect(results.map(\.id) == [CommandID("cafe")])
    }

    @Test
    func matchesKeywordsAndSimpleFuzzyQueries() {
        let commands = [
            descriptor("terminal", title: "Terminal", keywords: ["shell"]),
            descriptor("xcode", title: "Xcode"),
        ]

        #expect(engine.search(query: "shell", in: commands, limit: 8).first?.id == CommandID("terminal"))
        #expect(engine.search(query: "xcd", in: commands, limit: 8).first?.id == CommandID("xcode"))
    }

    @Test
    func prefersTitleMatchesAndAppliesLimit() {
        let commands = [
            descriptor("keyword", title: "Editor", keywords: ["safari"]),
            descriptor("title", title: "Safari"),
            descriptor("prefix", title: "Safari Technology Preview"),
        ]

        let results = engine.search(query: "safari", in: commands, limit: 2)

        #expect(results.map(\.id) == [CommandID("title"), CommandID("prefix")])
    }

    @Test
    func usesStableTitleThenIDOrderingForEqualScores() {
        let commands = [
            descriptor("z", title: "Beta App", keywords: ["tool"]),
            descriptor("b", title: "Alpha App", keywords: ["tool"]),
            descriptor("a", title: "Alpha App", keywords: ["tool"]),
        ]

        let results = engine.search(query: "tool", in: commands, limit: 8)

        #expect(results.map(\.id) == [CommandID("a"), CommandID("b"), CommandID("z")])
    }

    @Test
    func preservesInputOrderForEmptyQuery() {
        let commands = [
            descriptor("second", title: "Second"),
            descriptor("first", title: "First"),
        ]

        let results = engine.search(query: "", in: commands, limit: 1)

        #expect(results.map(\.id) == [CommandID("second")])
    }

    private func descriptor(
        _ id: String,
        title: String,
        keywords: [String] = []
    ) -> CommandDescriptor {
        CommandDescriptor(
            id: CommandID(id),
            title: title,
            subtitle: nil,
            keywords: keywords
        )
    }
}

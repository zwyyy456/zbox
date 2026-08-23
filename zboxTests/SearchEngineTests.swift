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

    @Test
    func findsChineseApplicationByTitleFullPinyinAndInitials() {
        let aliases = ApplicationSearchAliases.make(for: "微信")
        let commands = [descriptor("wechat", title: "微信", aliases: aliases)]

        #expect(engine.search(query: "微信", in: commands, limit: 8).first?.id == CommandID("wechat"))
        #expect(engine.search(query: "wei xin", in: commands, limit: 8).first?.id == CommandID("wechat"))
        #expect(engine.search(query: "weixin", in: commands, limit: 8).first?.id == CommandID("wechat"))
        #expect(engine.search(query: "wx", in: commands, limit: 8).first?.id == CommandID("wechat"))
    }

    @Test
    func ranksLiteralTitleThenTransliterationThenInitialsThenFuzzy() {
        let query = "wx"
        let commands = [
            descriptor("fuzzy", title: "Work Xylophone"),
            descriptor(
                "initials",
                title: "首字母",
                aliases: [CommandSearchAlias(value: query, kind: .initials)]
            ),
            descriptor(
                "transliteration",
                title: "全拼",
                aliases: [CommandSearchAlias(value: query, kind: .transliteration)]
            ),
            descriptor("literal", title: query),
        ]

        let results = engine.search(query: query, in: commands, limit: 8)

        #expect(
            results.map(\.id) == [
                CommandID("literal"),
                CommandID("transliteration"),
                CommandID("initials"),
                CommandID("fuzzy"),
            ]
        )
    }

    private func descriptor(
        _ id: String,
        title: String,
        keywords: [String] = [],
        aliases: [CommandSearchAlias] = []
    ) -> CommandDescriptor {
        CommandDescriptor(
            id: CommandID(id),
            title: title,
            subtitle: nil,
            keywords: keywords,
            searchAliases: aliases
        )
    }
}

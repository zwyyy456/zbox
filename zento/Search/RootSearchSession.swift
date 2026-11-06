import AppKit
import Observation

@MainActor @Observable
final class RootSearchSession {
    private enum Key { static let recentCommands = "search.recent-command-ids" }
    private let defaults: UserDefaults
    private let aliases: CommandAliasStore
    private let searchEngine = SearchEngine()
    var descriptors: [CommandDescriptor] = []
    init(defaults: UserDefaults, aliases: CommandAliasStore) {
        self.defaults = defaults
        self.aliases = aliases
        recentCommandIDs = (defaults.stringArray(forKey: Key.recentCommands) ?? []).map(CommandID.init)
    }
    private enum RootSearchLimit {
        static let results = 8
        static let recent = 5
    }

    /// Entry commands suggested on an empty query after recent commands.
    private static let suggestedCommandIDs = [
        FileSearchPlugin.commandID, ClipboardHistoryPlugin.commandID, SnippetsPlugin.commandID,
        CalculatorPlugin.commandID, DeveloperToolsPlugin.commandID, SettingsCommands.openID,
    ]

    var targetApplicationPID: pid_t?
    var selectedCommandID: CommandID?
    var commandFeedback: CommandFeedback?
    var recentCommandIDs: [CommandID]
    var selectedRootSearchActionIndex = 0
    private(set) var id: UUID?
    var isShowingRootSearchActions = false {
        didSet { selectedRootSearchActionIndex = 0 }
    }
    func begin(targetPID: pid_t?) {
        id = UUID()
        targetApplicationPID = targetPID
        searchQuery = ""
        selectedCommandID = nil
        isShowingRootSearchActions = false
        commandFeedback = nil
    }

    func end() { id = nil }

    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                selectedCommandID = nil
                isShowingRootSearchActions = false
            }
        }
    }
    var searchResultSections: [SearchResultSection] {
        let descriptors = descriptors
        guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let matches = searchEngine.search(query: searchQuery, in: descriptors, limit: RootSearchLimit.results, aliases: aliases.aliases)
            return matches.isEmpty ? [] : [SearchResultSection(title: nil, matches: matches)]
        }

        let byID = Dictionary(descriptors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = recentCommandIDs.compactMap { byID[$0] }.prefix(RootSearchLimit.recent)
        let recentIDs = Set(recent.map(\.id))
        let suggested = Self.suggestedCommandIDs
            .filter { !recentIDs.contains($0) }
            .compactMap { byID[$0] }
            .prefix(RootSearchLimit.results - recent.count)
        return [
            SearchResultSection(title: String(localized: "Recent"),
                                matches: recent.map { SearchMatch(descriptor: $0, score: 0) }),
            SearchResultSection(title: String(localized: "Suggestions"),
                                matches: suggested.map { SearchMatch(descriptor: $0, score: 0) }),
        ].filter { !$0.matches.isEmpty }
    }

    var searchResults: [SearchMatch] {
        searchResultSections.flatMap(\.matches)
    }

    var selectedSearchMatch: SearchMatch? {
        let results = searchResults
        return results.first { $0.id == selectedCommandID } ?? results.first
    }

    func select(_ commandID: CommandID) {
        selectedCommandID = commandID
    }


    func moveSelection(by offset: Int) {
        let results = searchResults
        guard !results.isEmpty else {
            selectedCommandID = nil
            return
        }

        let currentIndex = selectedCommandID
            .flatMap { selectedID in results.firstIndex { $0.id == selectedID } }
            ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        selectedCommandID = results[nextIndex].id
    }

    func recordRecentCommand(_ commandID: CommandID) {
        recentCommandIDs.removeAll { $0 == commandID }
        recentCommandIDs.insert(commandID, at: 0)
        recentCommandIDs = Array(recentCommandIDs.prefix(RootSearchLimit.recent * 4))
        defaults.set(recentCommandIDs.map(\.rawValue), forKey: Key.recentCommands)
    }

    func clearRecentCommands() {
        recentCommandIDs = []
        defaults.removeObject(forKey: Key.recentCommands)
    }

}

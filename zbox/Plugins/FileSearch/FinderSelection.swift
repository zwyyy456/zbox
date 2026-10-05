import AppKit

nonisolated enum FinderSelectionError: LocalizedError {
    case target, permission, singleFile, unreadable, localOnly
    var errorDescription: String? {
        switch self {
        case .target: String(localized: "Select one file in Finder before invoking this command.")
        case .permission: String(localized: "Allow zbox to control Finder in System Settings > Privacy & Security > Automation, then try again.")
        case .singleFile: String(localized: "Select exactly one file or folder in Finder.")
        case .unreadable: String(localized: "The Finder selection could not be read.")
        case .localOnly: String(localized: "Only local files and folders are supported.")
        }
    }
}

@MainActor enum FinderSelection {
    static func read() throws -> URL {
        try Task.checkCancellation()
        let source = """
        with timeout of 2 seconds
        tell application "Finder"
            set chosenItems to selection
            if (count of chosenItems) is not 1 then return ""
            return URL of item 1 of chosenItems
        end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { throw FinderSelectionError.unreadable }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        try Task.checkCancellation()
        if let error {
            if (error["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue == -1743 { throw FinderSelectionError.permission }
            throw FinderSelectionError.unreadable
        }
        guard let value = result.stringValue, !value.isEmpty else { throw FinderSelectionError.singleFile }
        guard let url = URL(string: value), url.isFileURL else { throw FinderSelectionError.unreadable }
        guard try url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true else { throw FinderSelectionError.localOnly }
        return url
    }
}

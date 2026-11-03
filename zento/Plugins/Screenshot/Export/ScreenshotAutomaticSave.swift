import Foundation

nonisolated enum ScreenshotAutomaticSave {
    @concurrent
    static func write(_ data: Data, format: ScreenshotFormat, directory: URL) async throws -> URL {
        try Task.checkCancellation()
        let date = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = directory.appendingPathComponent("Screenshot-\(date)-\(UUID().uuidString).\(format.rawValue)")
        try data.write(to: url, options: [.withoutOverwriting])
        return url
    }
}

import Foundation

/// Retained only for this session's explicit retry. Never persisted or automatically retried.
nonisolated struct ScreenshotUploadSnapshot: Sendable {
    let profile: ScreenshotHostingProfile
    let image: Data
    let format: ScreenshotFormat
    let filename: String
    let copiesLink: Bool
}

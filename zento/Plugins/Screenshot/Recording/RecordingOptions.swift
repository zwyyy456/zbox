import CoreGraphics
import Foundation
import UniformTypeIdentifiers

nonisolated enum RecordingKind: String, CaseIterable, Sendable {
    case video, gif

    var title: String {
        switch self {
        case .video: String(localized: "Record Video")
        case .gif: String(localized: "Record GIF")
        }
    }

    var commandID: CommandID { CommandID("screenshot.record.\(rawValue)") }
    var fileType: UTType { self == .video ? .mpeg4Movie : .gif }
    var format: String { self == .video ? "MP4" : "GIF" }
    var frameRates: [Int] { self == .video ? [60, 30] : [10, 15, 20] }
}

nonisolated struct RecordingOptions: Codable, Sendable {
    static let gifLimit = 30
    static let scales = [100, 75, 50, 25]

    var frameRate: Int
    var scale = 100
    var showsCursor = true
    var capturesAudio = false

    init(kind: RecordingKind, saved: Data?) {
        if let saved, let options = try? JSONDecoder().decode(Self.self, from: saved),
           kind.frameRates.contains(options.frameRate), Self.scales.contains(options.scale) {
            self = options
        } else {
            frameRate = kind.frameRates[0]
        }
        if kind == .gif { capturesAudio = false }
    }

    func outputSize(for original: CGSize) -> CGSize {
        let ratio = Double(scale) / 100
        return CGSize(width: max(1, (original.width * ratio).rounded()),
                      height: max(1, (original.height * ratio).rounded()))
    }
}

nonisolated enum RecordingError: LocalizedError {
    case captureInProgress, targetUnavailable, controlWindowUnavailable, emptyVideo, unexpectedSize, gifEncoding

    var errorDescription: String? {
        switch self {
        case .captureInProgress: String(localized: "Finish or cancel the screenshot before starting a recording.")
        case .targetUnavailable: String(localized: "The selected recording target is no longer available.")
        case .controlWindowUnavailable: String(localized: "The recording controls could not be excluded from the capture.")
        case .emptyVideo: String(localized: "The recording contains no playable video.")
        case .unexpectedSize: String(localized: "The recording did not use the selected pixel dimensions.")
        case .gifEncoding: String(localized: "The GIF could not be encoded.")
        }
    }
}

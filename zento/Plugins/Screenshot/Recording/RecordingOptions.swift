import AVFoundation
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

    var optionsKey: String { "plugin.screenshot.recording.\(rawValue).options" }

    var commandID: CommandID { CommandID("screenshot.record.\(rawValue)") }
    var fileType: UTType { self == .video ? .mpeg4Movie : .gif }
    var format: String { self == .video ? "MP4" : "GIF" }
    var frameRates: [Int] { self == .video ? [60, 30] : [10, 15, 20] }
}

nonisolated enum RecordingVideoCodec: String, Codable, CaseIterable, Sendable {
    case hevc, h264

    var title: String { self == .hevc ? "HEVC (H.265)" : "H.264" }
    var avCodec: AVVideoCodecType { self == .hevc ? .hevc : .h264 }
}

nonisolated enum RecordingStartDelay: Int, Codable, CaseIterable, Sendable {
    case immediately = 0
    case threeSeconds = 3

    var title: String {
        switch self {
        case .immediately: String(localized: "Start Immediately")
        case .threeSeconds: String(localized: "Wait 3 Seconds")
        }
    }
}

nonisolated struct RecordingOptions: Codable, Sendable {
    static let gifLimit = 30
    static let scales = [100, 75, 50, 25]

    var frameRate: Int
    var scale = 100
    var showsCursor = true
    var capturesAudio = false
    var videoCodec: RecordingVideoCodec?
    var startDelay: RecordingStartDelay?

    var selectedStartDelay: RecordingStartDelay {
        get { startDelay ?? .threeSeconds }
        set { startDelay = newValue }
    }

    var selectedVideoCodec: RecordingVideoCodec {
        get { videoCodec ?? .hevc }
        set { videoCodec = newValue }
    }

    init(kind: RecordingKind, saved: Data?) {
        if let saved, let options = try? JSONDecoder().decode(Self.self, from: saved),
           kind.frameRates.contains(options.frameRate), Self.scales.contains(options.scale) {
            self = options
        } else {
            frameRate = kind.frameRates[0]
        }
        if kind == .gif { capturesAudio = false }
    }

    func outputSize(for original: CGSize, kind: RecordingKind) -> CGSize {
        let ratio = Double(scale) / 100
        if kind == .gif {
            return CGSize(width: max(1, (original.width * ratio).rounded()),
                          height: max(1, (original.height * ratio).rounded()))
        }
        // Video codecs use even pixel dimensions. Align before capture so the encoder,
        // preview and validation agree instead of discovering a one-pixel change at the end.
        return CGSize(width: max(2, floor((original.width * ratio).rounded() / 2) * 2),
                      height: max(2, floor((original.height * ratio).rounded() / 2) * 2))
    }
}

nonisolated enum RecordingError: LocalizedError {
    case captureInProgress, targetUnavailable, controlWindowUnavailable, emptyVideo, unexpectedSize, gifEncoding, unsupportedCodec

    var errorDescription: String? {
        switch self {
        case .captureInProgress: String(localized: "Finish or cancel the screenshot before starting a recording.")
        case .targetUnavailable: String(localized: "The selected recording target is no longer available.")
        case .controlWindowUnavailable: String(localized: "The recording controls could not be excluded from the capture.")
        case .emptyVideo: String(localized: "The recording contains no playable video.")
        case .unexpectedSize: String(localized: "The recording did not use the selected pixel dimensions.")
        case .unsupportedCodec: String(localized: "The selected video codec is not available on this Mac.")
        case .gifEncoding: String(localized: "The GIF could not be encoded.")
        }
    }
}

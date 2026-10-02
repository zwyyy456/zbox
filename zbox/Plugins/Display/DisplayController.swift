import AppKit
import CoreGraphics

nonisolated struct DisplayModeSpec: Codable, Hashable, Sendable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshMillihertz: Int

    var isHiDPI: Bool { pixelWidth > width && pixelHeight > height }
    var resolution: DisplayModeSpec {
        DisplayModeSpec(width: width, height: height, pixelWidth: pixelWidth, pixelHeight: pixelHeight, refreshMillihertz: 0)
    }
    var resolutionLabel: String { "\(width) × \(height)" }
    var refreshLabel: String {
        refreshMillihertz == 0 ? String(localized: "System managed")
            : String(format: "%.2f Hz", Double(refreshMillihertz) / 1000)
    }
}

nonisolated struct DisplayInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let vendor: UInt32
    let product: UInt32
    let rotation: Double
    let current: DisplayModeSpec
    let modes: [DisplayModeSpec]
}

nonisolated struct DisplaySelection: Codable, Equatable, Sendable {
    let displayID: String
    let displayName: String
    let mode: DisplayModeSpec
}

nonisolated enum DisplayError: LocalizedError {
    case unavailable, modeUnavailable, configurationFailed(Int32), disabled, busy
    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "A required display is missing or cannot be identified uniquely.")
        case .modeUnavailable: String(localized: "The saved display mode is no longer available.")
        case .configurationFailed(let code): String(localized: "macOS could not apply the display configuration (\(code)).")
        case .disabled: String(localized: "Enable Display in Settings first.")
        case .busy: String(localized: "Keep or revert the current display change first.")
        }
    }
}

@MainActor
protocol DisplayConfiguring {
    func read() -> [DisplayInfo]
    func apply(_ selections: [DisplaySelection], permanent: Bool) throws
}

@MainActor
struct DisplayController: DisplayConfiguring {
    func read() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
                  let current = CGDisplayCopyDisplayMode(number.uint32Value) else { return nil }
            let id = number.uint32Value
            let specs = Set(modes(for: id).map(Self.spec))
            return DisplayInfo(id: CFUUIDCreateString(nil, uuid) as String, name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0, vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id),
                rotation: CGDisplayRotation(id), current: Self.spec(current),
                modes: specs.sorted {
                    if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI }
                    if $0.width != $1.width { return $0.width > $1.width }
                    if $0.height != $1.height { return $0.height > $1.height }
                    if $0.pixelWidth != $1.pixelWidth { return $0.pixelWidth > $1.pixelWidth }
                    if $0.pixelHeight != $1.pixelHeight { return $0.pixelHeight > $1.pixelHeight }
                    return $0.refreshMillihertz > $1.refreshMillihertz
                })
        }
    }

    func apply(_ selections: [DisplaySelection], permanent: Bool) throws {
        var resolved: [(CGDirectDisplayID, CGDisplayMode)] = []
        for selection in selections {
            let matches = NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
                      CFUUIDCreateString(nil, uuid) as String == selection.displayID else { return nil }
                return number.uint32Value
            }
            guard matches.count == 1, let displayID = matches.first else { throw DisplayError.unavailable }
            let current = CGDisplayCopyDisplayMode(displayID)
            let candidates = modes(for: displayID)
            let mode = current.flatMap { Self.spec($0) == selection.mode ? $0 : nil }
                ?? candidates.first { Self.spec($0) == selection.mode }
            guard let mode else { throw DisplayError.modeUnavailable }
            resolved.append((displayID, mode))
        }
        var configuration: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&configuration))
        guard let configuration else { throw DisplayError.configurationFailed(CGError.failure.rawValue) }
        do {
            for (id, mode) in resolved {
                try check(CGConfigureDisplayWithDisplayMode(configuration, id, mode, nil))
            }
        } catch {
            CGCancelDisplayConfiguration(configuration)
            throw error
        }
        // Complete consumes the configuration even when it reports failure.
        try check(CGCompleteDisplayConfiguration(configuration, permanent ? .permanently : .forAppOnly))
    }

    private func check(_ result: CGError) throws {
        guard result == .success else { throw DisplayError.configurationFailed(result.rawValue) }
    }

    private func modes(for id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? [])
            .filter { $0.isUsableForDesktopGUI() }
    }

    private static func spec(_ mode: CGDisplayMode) -> DisplayModeSpec {
        DisplayModeSpec(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
                        pixelHeight: mode.pixelHeight, refreshMillihertz: Int((mode.refreshRate * 1000).rounded()))
    }
}

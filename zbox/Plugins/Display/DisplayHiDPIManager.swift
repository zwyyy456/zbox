import Foundation
import Observation

nonisolated struct DisplayHiDPIInstallation: Codable, Identifiable, Sendable {
    var id: String { "\(vendor)-\(product)" }
    let vendor: UInt32
    let product: UInt32
    let displayName: String
    let plistData: Data
    let requested: [DisplayModeSpec]
    let previous: [DisplayModeSpec]
    var file: DisplayOverrideFile { DisplayOverrideFile(vendor: vendor, product: product, data: plistData) }

    func additionalModes(on display: DisplayInfo) -> Int {
        Set(display.modes.filter { mode in
            guard mode.isHiDPI else { return false }
            let unrotated: DisplayModeSpec
            if Int(display.rotation) % 180 != 0 {
                unrotated = DisplayModeSpec(width: mode.height, height: mode.width, pixelWidth: mode.pixelHeight,
                    pixelHeight: mode.pixelWidth, refreshMillihertz: 0)
            } else { unrotated = mode.resolution }
            return requested.contains(unrotated) && !previous.contains(mode.resolution)
        }.map(\.resolution)).count
    }
}

@MainActor
@Observable
final class DisplayHiDPIManager {
    private let defaults: UserDefaults
    private static let key = "display.hidpi-installations"
    private(set) var installations: [DisplayHiDPIInstallation] = []
    private(set) var isBusy = false
    private(set) var loadError: String?
    var statusMessage: String?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else { return }
        do { installations = try JSONDecoder().decode([DisplayHiDPIInstallation].self, from: data) }
        catch { loadError = String(localized: "HiDPI installation records could not be read. Existing data was preserved.") }
    }

    func install(on display: DisplayInfo, configuration: DisplayHiDPIConfiguration) async -> Bool {
        guard !isBusy, loadError == nil else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            guard !display.isBuiltIn else { throw DisplayHiDPIError.builtIn }
            guard configuration.vendor == display.vendor, configuration.product == display.product else { throw DisplayError.unavailable }
            let current = DisplayController().read().filter { $0.id == display.id }
            guard current.count == 1, current[0].vendor == display.vendor, current[0].product == display.product else {
                throw DisplayError.unavailable
            }
            let installation = DisplayHiDPIInstallation(vendor: display.vendor, product: display.product,
                displayName: display.name, plistData: try configuration.plistData(),
                requested: configuration.logicalSizes.map {
                    DisplayModeSpec(width: Int($0.width), height: Int($0.height), pixelWidth: Int($0.width) * 2,
                                    pixelHeight: Int($0.height) * 2, refreshMillihertz: 0)
                }, previous: current[0].modes.map(\.resolution))
            guard !FileManager.default.fileExists(atPath: installation.file.path) else { throw DisplayHiDPIError.existingOverride }
            // Persist removal data before authorization so a quit cannot orphan an installed file.
            try persist(installations.filter { $0.id != installation.id } + [installation])
            try await installation.file.install()
            statusMessage = String(localized: "Configuration installed. Restart macOS, then refresh displays to check which HiDPI modes became available.")
            return true
        } catch { statusMessage = error.localizedDescription; return false }
    }

    func remove(_ installation: DisplayHiDPIInstallation) async {
        guard !isBusy, loadError == nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let exists = FileManager.default.fileExists(atPath: installation.file.path)
            if exists { try await installation.file.remove() }
            try persist(installations.filter { $0.id != installation.id })
            statusMessage = exists
                ? String(localized: "The zbox override was removed. Restart macOS to reload the original display configuration.")
                : String(localized: "The installation record was cleared. No override file was present.")
        } catch { statusMessage = error.localizedDescription }
    }

    private func persist(_ updated: [DisplayHiDPIInstallation]) throws {
        defaults.set(try JSONEncoder().encode(updated), forKey: Self.key)
        installations = updated
    }
}

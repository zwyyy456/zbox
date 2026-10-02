import CoreGraphics

import Foundation

/// The override format uses two big-endian UInt32 backing dimensions per mode.
nonisolated struct DisplayHiDPIConfiguration: Codable, Equatable, Sendable {
    let vendor: UInt32
    let product: UInt32
    let nativeWidth: Int
    let nativeHeight: Int

    init(vendor: UInt32, product: UInt32, nativeWidth: Int, nativeHeight: Int) throws {
        guard vendor != 0, (640...16384).contains(nativeWidth), (480...16384).contains(nativeHeight) else {
            throw DisplayHiDPIError.invalidDimensions
        }
        self.vendor = vendor
        self.product = product
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
    }

    var directory: String {
        "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-\(String(vendor, radix: 16))"
    }
    var path: String { "\(directory)/DisplayProductID-\(String(product, radix: 16))" }

    var logicalSizes: [CGSize] {
        stride(from: nativeWidth, through: nativeWidth / 2, by: -16).map { width in
            CGSize(width: width, height: Int((Double(width) * Double(nativeHeight) / Double(nativeWidth)).rounded()))
        }
    }

    func plistData() throws -> Data {
        let resolutions = logicalSizes.map { size in
            var data = Data()
            for value in [UInt32(size.width) * 2, UInt32(size.height) * 2] {
                var bigEndian = value.bigEndian
                withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
            }
            return data
        }
        return try PropertyListSerialization.data(fromPropertyList: [
            "DisplayVendorID": vendor, "DisplayProductID": product,
            "scale-resolutions": resolutions
        ], format: .xml, options: 0)
    }
}

nonisolated enum DisplayHiDPIError: LocalizedError {
    case invalidDimensions, existingOverride, modifiedOverride, administratorFailed, builtIn
    var errorDescription: String? {
        switch self {
        case .invalidDimensions: String(localized: "Enter the panel's native unrotated resolution: width 640–16384 and height 480–16384.")
        case .existingOverride: String(localized: "A display override already exists. Remove it using the tool that created it before installing a zbox override.")
        case .modifiedOverride: String(localized: "The installed override differs from zbox's saved configuration. It was not removed.")
        case .administratorFailed: String(localized: "The administrator operation was cancelled or failed. No success was confirmed.")
        case .builtIn: String(localized: "Additional HiDPI configuration is supported only for external displays.")
        }
    }
}

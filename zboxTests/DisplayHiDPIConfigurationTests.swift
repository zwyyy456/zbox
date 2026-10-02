import Foundation
import Testing
@testable import zbox

struct DisplayHiDPIConfigurationTests {
    @Test func encodesBackingPixelsAsBigEndianAndUsesUnpaddedModelID() throws {
        let config = try DisplayHiDPIConfiguration(vendor: 0x1e6d, product: 0, nativeWidth: 2560, nativeHeight: 1440)
        #expect(config.path.hasSuffix("DisplayVendorID-1e6d/DisplayProductID-0"))
        let plist = try #require(PropertyListSerialization.propertyList(from: config.plistData(), format: nil) as? [String: Any])
        let entries = try #require(plist["scale-resolutions"] as? [Data])
        #expect(entries.first == Data([0, 0, 0x14, 0, 0, 0, 0x0b, 0x40]))
        #expect(entries.last == Data([0, 0, 0x0a, 0, 0, 0, 0x05, 0xa0]))
        #expect(Set(entries).count == entries.count)
        #expect(entries.allSatisfy { $0.count == 8 })
    }

    @Test func rejectsInvalidInputBeforeConstructingSystemConfiguration() {
        #expect(throws: DisplayHiDPIError.self) {
            try DisplayHiDPIConfiguration(vendor: 1, product: 2, nativeWidth: Int.max, nativeHeight: 1440)
        }
        #expect(throws: DisplayHiDPIError.self) {
            try DisplayHiDPIConfiguration(vendor: 0, product: 2, nativeWidth: 2560, nativeHeight: 1440)
        }
    }
}

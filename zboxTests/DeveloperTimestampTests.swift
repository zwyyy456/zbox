import Foundation
import Testing
@testable import zbox

struct DeveloperTimestampTests {
    @Test func preservesUnitsAndNegativeMilliseconds() throws {
        for (input, expected) in [("0", Int64(0)), ("-0.001", -1), ("-1.23", -1230), ("1.001", 1001), ("9007199254.741", 9_007_199_254_741)] {
            let value = try TimestampConverter.fromTimestamp(input, unit: .seconds)
            #expect(value.milliseconds == expected)
            #expect(try TimestampConverter.fromTimestamp(value.seconds, unit: .seconds).milliseconds == expected)
            #expect(try TimestampConverter.fromDate(value.utc).milliseconds == expected)
        }
        #expect(try TimestampConverter.fromTimestamp("1000", unit: .milliseconds).seconds == "1")
        #expect(try TimestampConverter.fromTimestamp("-1", unit: .milliseconds).utc == "1969-12-31T23:59:59.999Z")
        for input in ["1.0001", "1e3", "+1", "9223372036854775807", "253402300800", "-62135596800.001"] {
            #expect(throws: DeveloperToolError.self) { try TimestampConverter.fromTimestamp(input, unit: .seconds) }
        }
        #expect(throws: DeveloperToolError.self) { try TimestampConverter.fromTimestamp("1.1", unit: .milliseconds) }
    }

    @Test func dateInputRequiresARealDateAndExplicitOffset() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let result = try TimestampConverter.fromDate("1970-01-01T08:00:00.001+08:00", timeZone: zone)
        #expect(result.milliseconds == 1)
        #expect(result.local == "1970-01-01T08:00:00.001+08:00")
        #expect(try TimestampConverter.fromDate("1969-12-31T23:59:59.999Z").milliseconds == -1)
        #expect(try TimestampConverter.fromDate("2024-02-29T00:00:00Z").utc == "2024-02-29T00:00:00.000Z")
        for input in ["1500-02-29T00:00:00Z", "2023-02-29T00:00:00Z", "2026-13-01T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T00:00:60Z", "2026-01-01T00:00:00", "2026-01-01T00:00:00.1234Z", "2026-01-01T00:00:00+08:60", "0000-01-01T00:00:00Z"] {
            #expect(throws: DeveloperToolError.self) { try TimestampConverter.fromDate(input) }
        }
        #expect(try TimestampConverter.fromDate("0001-01-01T00:00:00Z").milliseconds == -62_135_596_800_000)
        #expect(try TimestampConverter.fromDate("1582-10-10T00:00:00Z").utc == "1582-10-10T00:00:00.000Z")
        for source in ["0001-01-01T00:00:00Z", "9999-12-31T23:59:59.999Z"] {
            let value = try TimestampConverter.fromDate(source)
            #expect(try TimestampConverter.fromDate(value.utc).milliseconds == value.milliseconds)
        }
    }
}

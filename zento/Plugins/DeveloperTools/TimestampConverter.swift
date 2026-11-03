import Foundation

nonisolated enum TimestampConverter {
    enum Unit: String, CaseIterable, Sendable {
        case seconds, milliseconds
        var title: String {
            switch self {
            case .seconds: String(localized: "Seconds")
            case .milliseconds: String(localized: "Milliseconds")
            }
        }
    }

    struct Result: Sendable {
        let milliseconds: Int64
        let utc: String
        let local: String
        let localTimeZone: String
        var seconds: String { TimestampConverter.secondsText(milliseconds) }
    }

    static func fromTimestamp(_ source: String, unit: Unit, timeZone: TimeZone = .current) throws -> Result {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = unit == .seconds ? #"^-?[0-9]+(?:\.[0-9]{1,3})?$"# : #"^-?[0-9]+$"#
        guard text.utf8.count <= 32, text.range(of: pattern, options: .regularExpression) != nil else {
            throw DeveloperToolError(message: String(localized: "Enter integer milliseconds or seconds with at most three decimal places."))
        }
        let milliseconds: Int64
        if unit == .milliseconds {
            guard let value = Int64(text) else { throw outOfRange }
            milliseconds = value
        } else {
            let magnitude = text.hasPrefix("-") ? String(text.dropFirst()) : text
            let parts = magnitude.split(separator: ".")
            guard let whole = Int64(parts[0]) else { throw outOfRange }
            let fraction = parts.count == 2 ? String(parts[1]) : ""
            let partial = Int64(fraction + String(repeating: "0", count: 3 - fraction.count))!
            let (scaled, overflow) = whole.multipliedReportingOverflow(by: 1000)
            let (combined, additionOverflow) = scaled.addingReportingOverflow(partial)
            guard !overflow, !additionOverflow else { throw outOfRange }
            milliseconds = text.hasPrefix("-") ? -combined : combined
        }
        return try result(milliseconds: milliseconds, timeZone: timeZone)
    }

    static func fromDate(_ source: String, timeZone: TimeZone = .current) throws -> Result {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        // The accepted ISO 8601 form requires an explicit offset and millisecond precision or less.
        let pattern = #"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,3}))?(Z|[+-][0-9]{2}:[0-9]{2})$"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard text.utf8.count <= 35,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { throw invalidDate }
        func field(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
        let zone = field(8)
        var offset = 0
        if zone != "Z" {
            let parts = zone.dropFirst().split(separator: ":")
            let hours = Int(parts[0])!
            let minutes = Int(parts[1])!
            guard hours <= 23, minutes <= 59 else { throw invalidDate }
            offset = (hours * 3600 + minutes * 60) * (zone.hasPrefix("-") ? -1 : 1)
        }
        guard let inputZone = TimeZone(secondsFromGMT: offset) else { throw invalidDate }
        let formatter = dateFormatter(timeZone: inputZone)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let dateText = String(text.prefix(19))
        guard Int(field(1))! >= 1, let date = formatter.date(from: dateText),
              formatter.string(from: date) == dateText else { throw invalidDate }
        let fraction = field(7)
        let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
            + Int64(fraction + String(repeating: "0", count: 3 - fraction.count))!
        return try result(milliseconds: milliseconds, timeZone: timeZone)
    }

    static func result(milliseconds: Int64, timeZone: TimeZone = .current) throws -> Result {
        guard (-62_135_596_800_000...253_402_300_799_999).contains(milliseconds) else { throw outOfRange }
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        let formatter = dateFormatter(timeZone: TimeZone(secondsFromGMT: 0)!)
        let utc = formatter.string(from: date)
        formatter.timeZone = timeZone
        return Result(milliseconds: milliseconds, utc: utc, local: formatter.string(from: date),
                      localTimeZone: timeZone.identifier)
    }

    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        // Apply Gregorian rules throughout the supported range instead of the historical 1582 cutover.
        formatter.gregorianStartDate = .distantPast
        formatter.timeZone = timeZone
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }

    private static func secondsText(_ milliseconds: Int64) -> String {
        let magnitude = milliseconds.magnitude
        let whole = magnitude / 1000
        let remainder = magnitude % 1000
        var fraction = String(format: "%03d", Int(remainder))
        while fraction.last == "0" { fraction.removeLast() }
        return (milliseconds < 0 ? "-" : "") + String(whole) + (fraction.isEmpty ? "" : "." + fraction)
    }

    private static var invalidDate: DeveloperToolError {
        DeveloperToolError(message: String(localized: "Enter a valid ISO 8601 date with a time zone, for example 2026-10-03T10:30:00.123+08:00."))
    }
    private static var outOfRange: DeveloperToolError {
        DeveloperToolError(message: String(localized: "The timestamp must fall within UTC years 0001–9999."))
    }
}

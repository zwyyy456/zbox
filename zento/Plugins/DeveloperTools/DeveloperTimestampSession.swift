import Foundation
import Observation

@MainActor
@Observable
final class DeveloperTimestampSession {
    var input = "" { didSet { clearResult() } }
    var fromDate = false { didSet { clearResult() } }
    var unit: TimestampConverter.Unit = .seconds { didSet { clearResult() } }
    private(set) var result: TimestampConverter.Result?
    private(set) var error: String?

    func run() {
        clearResult()
        do {
            result = try fromDate ? TimestampConverter.fromDate(input) : TimestampConverter.fromTimestamp(input, unit: unit)
        } catch { self.error = error.localizedDescription }
    }

    func useCurrentTime() {
        let milliseconds = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
        do {
            let current = try TimestampConverter.result(milliseconds: milliseconds)
            input = fromDate ? current.utc : (unit == .seconds ? current.seconds : String(milliseconds))
            result = current
        } catch { self.error = error.localizedDescription }
    }

    private func clearResult() { result = nil; error = nil }
}

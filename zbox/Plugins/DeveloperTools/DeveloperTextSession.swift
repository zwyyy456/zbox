import Foundation
import Observation

@MainActor
@Observable
final class DeveloperTextSession {
    enum Kind { case url, base64 }
    let kind: Kind
    var input = "" { didSet { invalidate() } }
    var decoding = false { didSet { invalidate() } }
    var urlSafe = false { didSet { invalidate() } }
    private(set) var output: String?
    private(set) var error: String?
    private(set) var isRunning = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(kind: Kind) { self.kind = kind }

    func invalidate() {
        task?.cancel()
        task = nil
        isRunning = false
        output = nil
        error = nil
    }

    func run() {
        invalidate()
        guard input.utf8.count <= 1_048_576 else {
            error = String(localized: "Input exceeds the 1 MiB limit.")
            return
        }
        let operation: Operation = kind == .url ? .url(decoding: decoding) : .base64(decoding: decoding, urlSafe: urlSafe)
        let input = input
        isRunning = true
        task = Task { [weak self] in
            do {
                let result = try await Self.transform(input, operation: operation)
                guard !Task.isCancelled, let self else { return }
                self.output = result
                self.isRunning = false
                self.task = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.error = error.localizedDescription
                self.isRunning = false
                self.task = nil
            }
        }
    }

    nonisolated private enum Operation: Sendable {
        case url(decoding: Bool)
        case base64(decoding: Bool, urlSafe: Bool)
    }

    @concurrent private static func transform(_ input: String, operation: Operation) async throws -> String {
        try Task.checkCancellation()
        let result: String
        switch operation {
        case .url(let decoding):
            result = try decoding ? URLCodec.decode(input) : URLCodec.encode(input)
        case .base64(let decoding, let urlSafe):
            result = try decoding ? Base64Codec.decode(input, urlSafe: urlSafe) : Base64Codec.encode(input, urlSafe: urlSafe)
        }
        try Task.checkCancellation()
        return result
    }
}

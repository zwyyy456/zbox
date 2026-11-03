import Foundation
import Observation

@MainActor
@Observable
final class DeveloperTextSession {
    enum Kind { case json, url, base64 }
    let kind: Kind
    var jsonOperation: JSONFormatter.Operation = .format { didSet { invalidate() } }
    var indentation = 2 { didSet { invalidate() } }
    var input = "" { didSet { invalidate() } }
    var decoding = false { didSet { invalidate() } }
    var urlSafe = false { didSet { invalidate() } }
    private(set) var output: String?
    private(set) var error: String?
    private(set) var errorOffset: Int?
    private(set) var validated = false
    private(set) var isRunning = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(kind: Kind) { self.kind = kind }

    func invalidate() {
        task?.cancel()
        task = nil
        isRunning = false
        output = nil
        error = nil
        errorOffset = nil
        validated = false
    }

    func run() {
        invalidate()
        guard input.utf8.count <= 1_048_576 else {
            error = String(localized: "Input exceeds the 1 MiB limit.")
            return
        }
        let operation: Operation
        switch kind {
        case .json: operation = .json(jsonOperation, indentation: indentation)
        case .url: operation = .url(decoding: decoding)
        case .base64: operation = .base64(decoding: decoding, urlSafe: urlSafe)
        }
        let input = input
        isRunning = true
        task = Task { [weak self] in
            do {
                let result = try await Self.transform(input, operation: operation)
                guard !Task.isCancelled, let self else { return }
                if case .json(.validate, _) = operation {
                    self.validated = true
                } else {
                    self.output = result
                }
                self.isRunning = false
                self.task = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.error = error.localizedDescription
                self.errorOffset = (error as? JSONSyntaxError)?.utf16Offset
                self.isRunning = false
                self.task = nil
            }
        }
    }

    nonisolated private enum Operation: Sendable {
        case json(JSONFormatter.Operation, indentation: Int)
        case url(decoding: Bool)
        case base64(decoding: Bool, urlSafe: Bool)
    }

    @concurrent private static func transform(_ input: String, operation: Operation) async throws -> String {
        try Task.checkCancellation()
        let result: String
        switch operation {
        case .json(let operation, let indentation):
            result = try JSONFormatter.process(input, operation: operation, indentation: indentation)
        case .url(let decoding):
            result = try decoding ? URLCodec.decode(input) : URLCodec.encode(input)
        case .base64(let decoding, let urlSafe):
            result = try decoding ? Base64Codec.decode(input, urlSafe: urlSafe) : Base64Codec.encode(input, urlSafe: urlSafe)
        }
        try Task.checkCancellation()
        return result
    }
}

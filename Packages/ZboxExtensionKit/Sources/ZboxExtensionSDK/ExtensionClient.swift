import Foundation
import Darwin
import ZboxExtensionProtocol

public struct ExtensionEvent: Sendable {
    public let method: String
    public let params: ExtensionValue
    public var id: Int { params["eventID"]!.int! }
}

public struct ExtensionContext: Sendable {
    private let client: ExtensionClient
    public let eventID: Int
    fileprivate init(client: ExtensionClient, eventID: Int) { self.client = client; self.eventID = eventID }

    public func show(_ view: ExtensionViewSnapshot) async throws { try await client.show(view, eventID: eventID) }
    public func call(_ method: String, params: [String: ExtensionValue] = [:]) async throws -> ExtensionValue {
        try await client.call(method, params: params, eventID: eventID)
    }
}

/// One client per executable session. The input loop stays available while an event awaits a host reply.
public actor ExtensionClient {
    public typealias Handler = @Sendable (ExtensionEvent, ExtensionContext) async throws -> Void
    private struct Pending {
        let eventID: Int
        let continuation: CheckedContinuation<ExtensionValue, any Error>
        let timeout: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]
    private var nextID = 0
    private var eventID: Int?
    private var handlerTask: Task<Void, Never>?
    private var lastView: ExtensionViewSnapshot?
    private var initialized = false
    private var ended = false
    public init() {}

    @concurrent public static func run(handler: @escaping Handler) async throws {
        let client = ExtensionClient()
        var decoder = ExtensionFrameDecoder()
        let flags = fcntl(STDIN_FILENO, F_GETFL)
        guard flags >= 0, fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw ExtensionProtocolError("Cannot read the host input pipe.")
        }
        defer { _ = fcntl(STDIN_FILENO, F_SETFL, flags) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        do {
            while true {
                let count = read(STDIN_FILENO, &buffer, buffer.count)
                if count == 0 { break }
                if count < 0 {
                    guard errno == EAGAIN || errno == EINTR else { throw ExtensionProtocolError("The host input pipe failed.") }
                    try await Task.sleep(for: .milliseconds(10))
                    continue
                }
                for message in try decoder.append(Data(buffer.prefix(count))) {
                    if try await client.receive(message, handler: handler) == false { await client.finish(); return }
                }
            }
            await client.finish()
            if decoder.hasPartialFrame { throw ExtensionProtocolError("Incomplete host message.") }
        } catch { await client.finish(); throw error }
    }

    private func receive(_ message: ExtensionMessage, handler: @escaping Handler) throws -> Bool {
        if message.method == nil, let id = message.id, let request = pending.removeValue(forKey: id) {
            request.timeout.cancel()
            if let error = message.error { request.continuation.resume(throwing: ExtensionProtocolError(error.message)) }
            else { request.continuation.resume(returning: message.result ?? .null) }
            return true
        }
        switch message.method {
        case "initialize":
            guard !initialized, let id = message.id, message.params?["protocolVersion"]?.int == 1 else { throw ExtensionProtocolError("Incompatible host protocol.") }
            initialized = true
            try send(ExtensionMessage(id: id, result: .object(["protocolVersion": .integer(1)])))
        case "start", "query", "action":
            guard initialized, let params = message.params, let id = params["eventID"]?.int, id > 0 else { throw ExtensionProtocolError("Missing event identity.") }
            cancelEvent()
            eventID = id
            let event = ExtensionEvent(method: message.method!, params: params)
            let context = ExtensionContext(client: self, eventID: id)
            handlerTask = Task {
                do { try await handler(event, context) }
                catch is CancellationError { }
                catch {
                    if !Task.isCancelled {
                        var view = lastView ?? ExtensionViewSnapshot()
                        view.error = error.localizedDescription
                        try? show(view, eventID: id)
                    }
                }
            }
        case "cancel":
            if message.params?["eventID"]?.int == eventID { cancelEvent() }
        case "stop": finish(); return false
        default: break
        }
        return true
    }

    fileprivate func show(_ view: ExtensionViewSnapshot, eventID: Int) throws {
        try check(eventID)
        try view.validate()
        lastView = view
        let value = try JSONDecoder().decode(ExtensionValue.self, from: JSONEncoder().encode(view))
        try send(ExtensionMessage(method: "ui", params: .object(["eventID": .integer(eventID), "view": value])))
    }

    fileprivate func call(_ method: String, params: [String: ExtensionValue], eventID: Int) async throws -> ExtensionValue {
        try check(eventID)
        guard pending.count < 64 else { throw ExtensionProtocolError("Too many pending host calls.") }
        nextID += 1
        let id = String(nextID)
        var params = params; params["eventID"] = .integer(eventID)
        let message = ExtensionMessage(id: id, method: method, params: .object(params))
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    await self?.fail(id, error: ExtensionProtocolError("Host request timed out."))
                }
                pending[id] = Pending(eventID: eventID, continuation: continuation, timeout: timeout)
                do { try send(message) } catch { fail(id, error: error) }
            }
        } onCancel: { Task { await self.fail(id, error: CancellationError()) } }
    }

    private func check(_ expected: Int) throws {
        try Task.checkCancellation()
        guard !ended, eventID == expected else { throw CancellationError() }
    }
    private func send(_ message: ExtensionMessage) throws {
        var data = try JSONEncoder().encode(message)
        guard data.count <= ExtensionFrameDecoder.limit else { throw ExtensionProtocolError("Message exceeds 8 MiB.") }
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
    private func fail(_ id: String, error: any Error) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel(); request.continuation.resume(throwing: error)
    }
    private func cancelEvent() {
        handlerTask?.cancel(); handlerTask = nil; eventID = nil
        for id in Array(pending.keys) { fail(id, error: CancellationError()) }
    }
    private func finish() { ended = true; cancelEvent() }
}

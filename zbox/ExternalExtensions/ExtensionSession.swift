import ZboxExtensionProtocol
import SwiftUI

@MainActor @Observable
final class ExtensionSession: NSObject, NSWindowDelegate {
    let command: ExtensionCommand
    let root: URL
    let host: ExtensionHostAPI
    private(set) var viewRevision = 0
    var snapshot = ExtensionViewSnapshot()
    var query = ""
    var fieldValues: [String: String] = [:]
    var selectedID: String?
    private var userEvent = true
    private var clipboardCount = 0
    private var usedSensitiveMethods = Set<String>()
    private struct PendingCall {
        let token: UUID
        let task: Task<Void, Never>
        let timeout: Task<Void, Never>
    }
    private var ending = false
    private var closed = false
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var hostTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pending: [String: PendingCall] = [:]
    let connection = ExtensionConnection()
    var values: [String]
    var hasPendingWork: Bool { running || !hostTasks.isEmpty }
    private(set) var running = false
    private(set) var ready = false
    private(set) var eventID = 0
    var error: String?
    var diagnostics = ""
    var needsAccessibility = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var handshakeTimeout: Task<Void, Never>?
    @ObservationIgnored private var window: NSWindow?

    init(command: ExtensionCommand, root: URL, host: ExtensionHostAPI) {
        self.command = command; self.root = root; self.host = host
        values = (command.parameters ?? []).map { $0.defaultValue ?? "" }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 520),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = command.name; window.minSize = CGSize(width: 480, height: 320)
            window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: ExtensionSessionView(session: self))
            window.center(); self.window = window
        }
        NSApp.activate(); window?.makeKeyAndOrderFront(nil)
    }

    func start() {
        guard !running else { return }
        do {
            let invocation = try command.invocation(root: root, values: values)
            running = true; ready = false; ending = false; closed = false; error = nil; eventID = 0
            needsAccessibility = false
            snapshot = ExtensionViewSnapshot(); fieldValues = [:]; query = ""; selectedID = nil
            clipboardCount = NSPasteboard.general.changeCount; userEvent = true; usedSensitiveMethods = []
            let initial = ExtensionMessage(id: "initialize", method: "initialize", params: .object([
                "protocolVersion": .integer(1), "sessionID": .string(UUID().uuidString)
            ]))
            handshakeTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, running, !ready else { return }
                error = "The extension did not complete initialization within 5 seconds."
                cancel()
            }
            task = Task {
                do {
                    let result = try await connection.run(invocation, initial: initial, stopping: { await self.transportStopped() }) { message in
                        try await self.receive(message)
                    }
                    if !closed { diagnostics = String(decoding: result.output.stderr, as: UTF8.self) }
                    if !result.cancelled && !ending { error = "The extension exited (status \(result.status))." }
                } catch { if !Task.isCancelled && !ending { self.error = error.localizedDescription } }
                cancelPending(); ready = false; running = false; handshakeTimeout?.cancel(); handshakeTimeout = nil; task = nil
            }
        } catch { self.error = error.localizedDescription }
    }

    private func receive(_ message: ExtensionMessage) async throws {
        guard running, !ending, !Task.isCancelled else { return }
        if message.id == "initialize", message.method == nil {
            guard !ready, message.error == nil, message.result?["protocolVersion"]?.int == 1 else {
                throw ExtensionFailure("The extension protocol version is incompatible.")
            }
            ready = true; eventID = 1; handshakeTimeout?.cancel()
            try await connection.send(ExtensionMessage(method: "start", params: .object([
                "commandID": .string(command.id), "arguments": .array(values.map(ExtensionValue.string)),
                "eventID": .integer(eventID)
            ])))
            return
        }
        guard ready else { throw ExtensionFailure("The extension sent a message before initialization.") }
        if message.method == "ui", message.id == nil {
            guard message.params?["eventID"]?.int == eventID else { return }
            guard let view = message.params?["view"] else { throw ExtensionFailure("Missing extension view.") }
            let next = try JSONDecoder().decode(ExtensionViewSnapshot.self, from: JSONEncoder().encode(view))
            try next.validate()
            let fields = next.fields ?? []
            fieldValues = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, fieldValues[$0.id] ?? $0.value ?? "") })
            if !(next.items ?? []).contains(where: { $0.id == selectedID }) { selectedID = next.items?.first?.id }
            viewRevision += 1
            snapshot = next
            return
        }
        guard let id = message.id, let method = message.method else { throw ExtensionFailure("Unexpected protocol message.") }
        guard pending.count < 64, pending[id] == nil else { throw ExtensionFailure("Too many or duplicate host requests.") }
        guard method == "settings.get" || ExtensionHostAPI.capabilities[method] != nil else {
            try await connection.send(ExtensionMessage(id: id, error: ExtensionRPCError(code: -32601, message: "Unknown host method.")))
            return
        }
        guard let params = message.params, params["eventID"]?.int == eventID else {
            try await connection.send(ExtensionMessage(id: id, error: ExtensionRPCError(code: -32000, message: "The extension event has ended.")))
            return
        }
        if method == "selection.read" || method.hasPrefix("clipboard.") {
            guard userEvent, usedSensitiveMethods.insert(method).inserted else {
                try await connection.send(ExtensionMessage(id: id, error: ExtensionRPCError(code: -32000, message: "This operation requires a new user action.")))
                return
            }
        }
        let event = eventID, token = UUID(), expectedCount = clipboardCount
        let operation = Task { [weak self] in
            guard let self else { return }
            defer { hostTasks[token] = nil }
            let response: ExtensionMessage
            do {
                let value = try await host.call(method, params: params, expectedClipboardCount: expectedCount) { [weak self] in
                    self?.ready == true && self?.eventID == event
                }
                response = ExtensionMessage(id: id, result: value)
                if method == "selection.read", ready, eventID == event { show() }
            } catch {
                if ready, eventID == event {
                    switch error {
                    case SelectedTextError.permissionRequired, ClipboardPasteError.permissionRequired: needsAccessibility = true
                    default: break
                    }
                }
                response = ExtensionMessage(id: id, error: ExtensionRPCError(code: -32000, message: error.localizedDescription))
            }
            guard ready, eventID == event, pending[id]?.token == token, !Task.isCancelled else { return }
            pending.removeValue(forKey: id)?.timeout.cancel()
            do { try await connection.send(response) } catch { fail(error) }
        }
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, pending[id]?.token == token else { return }
            pending.removeValue(forKey: id)?.task.cancel()
            do { try await connection.send(ExtensionMessage(id: id, error: ExtensionRPCError(code: -32000, message: "Host request timed out."))) }
            catch { fail(error) }
        }
        hostTasks[token] = operation
        pending[id] = PendingCall(token: token, task: operation, timeout: timeout)
    }

    func sendQuery(_ value: String) {
        guard ready else { return }
        query = value
        sendEvent("query", values: ["query": .string(value)], userAction: false)
    }

    func perform(_ action: ExtensionAction, revision: Int) {
        guard ready, revision == viewRevision, action.enabled != false, (snapshot.actions ?? []).contains(where: { $0.id == action.id }) else { return }
        sendEvent("action", values: ["actionID": .string(action.id),
            "values": .object(fieldValues.mapValues(ExtensionValue.string)),
            "selectedID": selectedID.map(ExtensionValue.string) ?? .null], userAction: true)
    }

    private func sendEvent(_ method: String, values: [String: ExtensionValue], userAction: Bool) {
        let previous = eventID
        eventID += 1; userEvent = userAction; usedSensitiveMethods = []
        if userAction { needsAccessibility = false }
        clipboardCount = NSPasteboard.general.changeCount
        cancelPending()
        var params = values
        let event = eventID
        params["eventID"] = .integer(event)
        Task {
            guard ready, eventID == event else { return }
            do {
                try await connection.send(ExtensionMessage(method: "cancel", params: .object(["eventID": .integer(previous)])))
                guard ready, eventID == event else { return }
                try await connection.send(ExtensionMessage(method: method, params: .object(params)))
            } catch { fail(error) }
        }
    }

    private func transportStopped() { ready = false; cancelPending(); handshakeTimeout?.cancel() }

    private func cancelPending() {
        for call in pending.values { call.task.cancel(); call.timeout.cancel() }
        pending.removeAll()
    }
    private func fail(_ error: any Error) { self.error = error.localizedDescription; cancel() }

    func cancel() {
        guard !ending else { return }
        ending = true; cancelPending(); ready = false; eventID += 1; handshakeTimeout?.cancel()
        let execution = task
        stopTask = Task {
            // The session is already invalid. Give cooperative SDK cleanup a short, bounded chance.
            try? await connection.send(ExtensionMessage(method: "stop"))
            try? await Task.sleep(for: .milliseconds(100))
            execution?.cancel()
        }
    }
    func stop() {
        closed = true; cancel(); window?.orderOut(nil); window?.contentView = nil; window = nil
        snapshot = ExtensionViewSnapshot(); fieldValues = [:]; query = ""; values = (command.parameters ?? []).map { $0.defaultValue ?? "" }; diagnostics = ""; error = nil
    }
    func waitForStop() async {
        await stopTask?.value
        await task?.value
        for call in hostTasks.values { await call.value }
    }
    func windowWillClose(_ notification: Notification) { stop() }
}

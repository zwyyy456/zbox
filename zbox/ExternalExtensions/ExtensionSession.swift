import SwiftUI

@MainActor @Observable
final class ExtensionSession: NSObject, NSWindowDelegate {
    let installation: ExtensionInstallation
    let command: ExtensionCommand
    let root: URL
    let context: CommandContext
    let connection = ExtensionConnection()
    var values: [String]
    private(set) var running = false
    private(set) var ready = false
    private(set) var eventID = 0
    var error: String?
    var diagnostics = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var handshakeTimeout: Task<Void, Never>?
    @ObservationIgnored private var window: NSWindow?

    init(installation: ExtensionInstallation, command: ExtensionCommand, root: URL, context: CommandContext) {
        self.installation = installation; self.command = command; self.root = root; self.context = context
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
            running = true; ready = false; error = nil; eventID = 0
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
                    let result = try await connection.run(invocation, initial: initial) { message in
                        try await self.receive(message)
                    }
                    diagnostics = String(decoding: result.output.stderr, as: UTF8.self)
                    if !result.cancelled { error = "The extension exited (status \(result.status))." }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                ready = false; running = false; handshakeTimeout?.cancel(); handshakeTimeout = nil; task = nil
            }
        } catch { self.error = error.localizedDescription }
    }

    private func receive(_ message: ExtensionMessage) async throws {
        guard running, !Task.isCancelled else { return }
        if message.id == "initialize", message.method == nil {
            guard !ready, message.error == nil, message.result?["protocolVersion"]?.int == 1 else {
                throw ExtensionFailure("The extension protocol version is incompatible.")
            }
            ready = true; eventID = 1; handshakeTimeout?.cancel()
            try await connection.send(ExtensionMessage(method: "start", params: .object([
                "commandID": .string(command.id), "arguments": .array(values.map(ExtensionValue.string)),
                "settings": .object(installation.settings.mapValues(ExtensionValue.string)), "eventID": .integer(eventID)
            ])))
            return
        }
        guard ready else { throw ExtensionFailure("The extension sent a message before initialization.") }
        if let id = message.id, message.method != nil {
            try await connection.send(ExtensionMessage(id: id, error: ExtensionRPCError(code: -32601, message: "Unknown host method.")))
        }
    }

    func cancel() { ready = false; eventID += 1; handshakeTimeout?.cancel(); task?.cancel() }
    func stop() { cancel(); window?.orderOut(nil); window?.contentView = nil; window = nil }
    func waitForStop() async { await task?.value }
    func windowWillClose(_ notification: Notification) { stop() }
}

struct ExtensionSessionView: View {
    @Bindable var session: ExtensionSession
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array((session.command.parameters ?? []).enumerated()), id: \.element.id) { index, field in
                TextField(field.name, text: $session.values[index]).disabled(session.running)
            }
            HStack {
                Button("Run", action: session.start).disabled(session.running)
                Button("Stop", action: session.cancel).disabled(!session.running)
                if session.running { ProgressView().controlSize(.small) }
            }
            Text(session.ready ? "Extension connected" : "Extension session")
            if let error = session.error { SettingsErrorView(message: error) }
            Spacer()
        }.padding(20)
    }
}

import SwiftUI

@MainActor @Observable
final class ExtensionTaskSession {
    let installation: ExtensionInstallation
    let command: ExtensionCommand
    let root: URL
    let coordinator: ClipboardAccessCoordinator
    var values: [String]
    private(set) var running = false
    private(set) var output = ScriptOutput()
    private(set) var result: ScriptRunResult?
    var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var window: NSWindow?

    init(installation: ExtensionInstallation, command: ExtensionCommand, root: URL, coordinator: ClipboardAccessCoordinator) {
        self.installation = installation; self.command = command; self.root = root; self.coordinator = coordinator
        values = (command.parameters ?? []).map { $0.defaultValue ?? "" }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 480),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = command.name
            window.minSize = CGSize(width: 480, height: 320)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ExtensionTaskView(session: self))
            window.center(); self.window = window
        }
        NSApp.activate(); window?.makeKeyAndOrderFront(nil)
    }

    func run() {
        guard !running else { return }
        do {
            let invocation = try command.invocation(root: root, values: values)
            running = true; output = ScriptOutput(); result = nil; error = nil
            task = Task {
                do {
                    result = try await ScriptRunner.run(invocation) { output in await self.update(output) }
                } catch { self.error = error.localizedDescription }
                running = false; task = nil
            }
        } catch { self.error = error.localizedDescription }
    }

    private func update(_ output: ScriptOutput) { self.output = output }
    func cancel() { task?.cancel() }
    func stop() { cancel(); window?.orderOut(nil); window?.contentView = nil; window = nil }
    func waitForStop() async { await task?.value }
    func copy(_ value: String) {
        let board = NSPasteboard.general
        board.prepareForNewContents(with: .currentHostOnly)
        let success = board.setString(value, forType: .string)
        coordinator.didWrite(changeCount: board.changeCount)
        if !success { error = String(localized: "Could not copy the result.") }
    }
}

private struct ExtensionTaskView: View {
    @Bindable var session: ExtensionTaskSession
    @State private var stderr = false
    private var text: String { String(decoding: stderr ? session.output.stderr : session.output.stdout, as: UTF8.self) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array((session.command.parameters ?? []).enumerated()), id: \.element.id) { index, field in
                TextField(field.name, text: $session.values[index]).disabled(session.running)
            }
            HStack {
                Button("Run", action: session.run).keyboardShortcut(.return, modifiers: .command).disabled(session.running)
                Button("Stop", action: session.cancel).disabled(!session.running)
                if session.running { ProgressView().controlSize(.small) }
                if let result = session.result {
                    Text(result.cancelled ? String(localized: "Cancelled") : result.timedOut ? String(localized: "Timed Out") : "Exit status: \(result.status)")
                }
            }
            Picker("Output", selection: $stderr) {
                Text("Standard Output").tag(false); Text("Standard Error").tag(true)
            }.pickerStyle(.segmented)
            PlainTextEditor(text: .constant(text), isEditable: false, label: String(localized: "Output"))
            Button("Copy Output") { session.copy(text) }.disabled(text.isEmpty)
            if session.output.truncated { Text("Output limited to 1 MiB per stream.").font(.caption) }
            if let error = session.error { SettingsErrorView(message: error) }
        }.padding(20)
    }
}

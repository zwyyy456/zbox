import SwiftUI

@MainActor @Observable
final class ExtensionManager {
    let store = ExtensionPackageStore()
    private let coordinator: ClipboardAccessCoordinator
    private(set) var items: [ExtensionInstallation] = []
    private(set) var busy = true
    private(set) var loadFailed = false
    private var stopping = false
    var error: String?
    var candidate: ExtensionInstallation?
    @ObservationIgnored var didCommit: ((Set<CommandID>) -> Void)?
    @ObservationIgnored var applyCommands: (() throws -> Void)?
    @ObservationIgnored private var sessions: [String: ExtensionTaskSession] = [:]

    init(coordinator: ClipboardAccessCoordinator) { self.coordinator = coordinator }
    var hasRunningTasks: Bool { busy || sessions.values.contains { $0.running } }
    var shortcutTargets: [CommandShortcutTarget] {
        items.flatMap { item in item.manifest.commands.map { CommandShortcutTarget(id: $0.commandID(in: item.id), title: $0.name) } }
    }
    var enabledCommandIDs: Set<CommandID> {
        Set(items.filter(\.enabled).flatMap { item in item.manifest.commands.map { $0.commandID(in: item.id) } })
    }

    func load() async {
        do { items = try await store.load(); try applyCommands?() }
        catch { self.error = error.localizedDescription; loadFailed = true }
        busy = false
    }

    func prepare(_ url: URL) async {
        guard !stopping, !busy, !loadFailed else { return }
        busy = true; error = nil
        defer { busy = false }
        do { candidate = try await store.prepare(url) }
        catch { self.error = error.localizedDescription }
    }

    func discardCandidate() async {
        guard let item = candidate else { return }
        candidate = nil
        do { try await store.discard(item) } catch { self.error = error.localizedDescription }
    }

    func install() async {
        guard !stopping, !busy, !loadFailed, var item = candidate else { return }
        busy = true; error = nil
        defer { busy = false }
        let previous = items.first { $0.id == item.id }
        await stop(item.id)
        item.settings = previous?.settings ?? [:]
        item.enabled = previous?.enabled ?? true
        do {
            try await replace(items.filter { $0.id != item.id } + [item])
            candidate = nil
            if let previous { try await store.discard(previous) }
        } catch { self.error = error.localizedDescription }
    }

    func setEnabled(_ item: ExtensionInstallation, _ enabled: Bool) async {
        guard !stopping, !busy, !loadFailed else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            if !enabled { await stop(item.id) }
            if enabled { try item.manifest.checkEnvironment() }
            var next = items
            if let index = next.firstIndex(where: { $0.id == item.id }) { next[index].enabled = enabled }
            try await replace(next)
        } catch { self.error = error.localizedDescription }
    }

    func uninstall(_ item: ExtensionInstallation, deleteData: Bool) async {
        guard !stopping, !busy, !loadFailed else { return }
        busy = true; error = nil
        defer { busy = false }
        await stop(item.id)
        do {
            try await replace(items.filter { $0.id != item.id })
            try await store.discard(item)
            if deleteData { try await store.removeData(item.id) }
        } catch { self.error = error.localizedDescription }
    }

    private func replace(_ next: [ExtensionInstallation]) async throws {
        let previous = items
        items = next
        do {
            try applyCommands?()
            try await store.save(next)
            let oldIDs = Set(previous.flatMap { item in item.manifest.commands.map { $0.commandID(in: item.id) } })
            didCommit?(oldIDs.subtracting(Set(shortcutTargets.map(\.id))))
        } catch {
            items = previous
            do { try applyCommands?() }
            catch { throw ExtensionFailure("The extension change and command restoration failed: \(error.localizedDescription)") }
            throw error
        }
    }

    func register(in registry: CommandRegistry) throws {
        for item in items where item.enabled {
            for command in item.manifest.commands {
                try registry.register(CommandDescriptor(id: command.commandID(in: item.id), title: command.name,
                    subtitle: item.manifest.name, keywords: command.keywords ?? [])) { [weak self] context in
                        try self?.execute(item.id, commandID: command.id, context: context)
                    }
            }
        }
    }

    private func execute(_ id: String, commandID: String, context: CommandContext) throws {
        guard !stopping, !busy, let item = items.first(where: { $0.id == id && $0.enabled }),
              let command = item.manifest.commands.first(where: { $0.id == commandID }) else { throw ExtensionFailure("The extension is unavailable.") }
        if let session = sessions[id], session.running { session.show(); return }
        guard command.mode == "task" else { throw ExtensionFailure("Interactive extensions are not available in this build.") }
        try item.manifest.checkEnvironment()
        sessions[id]?.stop()
        let session = ExtensionTaskSession(installation: item, command: command, root: store.packageURL(item), coordinator: coordinator)
        sessions[id] = session
        session.show()
        if (command.parameters ?? []).isEmpty { session.run() }
    }

    private func stop(_ id: String) async {
        let session = sessions.removeValue(forKey: id)
        session?.stop(); await session?.waitForStop()
    }
    func stop() { stopping = true; for session in sessions.values { session.stop() } }
    func waitForStop() async {
        while busy { try? await Task.sleep(for: .milliseconds(50)) }
        for session in sessions.values { await session.waitForStop() } }
}

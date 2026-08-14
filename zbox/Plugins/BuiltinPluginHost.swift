import Foundation

@MainActor
final class BuiltinPluginHost {
    private let plugins: [BuiltinPluginID: any BuiltinPlugin]
    private var runningPluginIDs: Set<BuiltinPluginID> = []

    init(plugins: [any BuiltinPlugin]) {
        self.plugins = Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, $0) })
    }

    func setEnabled(_ enabled: Bool, for id: BuiltinPluginID) {
        guard let plugin = plugins[id] else { return }

        if enabled, runningPluginIDs.insert(id).inserted {
            plugin.start()
        } else if !enabled, runningPluginIDs.remove(id) != nil {
            plugin.stop()
        }
    }

    func stopAll() {
        for id in runningPluginIDs {
            plugins[id]?.stop()
        }
        runningPluginIDs.removeAll()
    }
}

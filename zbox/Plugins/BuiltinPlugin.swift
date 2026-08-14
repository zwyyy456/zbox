import Foundation

nonisolated struct BuiltinPluginID: Hashable, Sendable {
    let rawValue: String
}

@MainActor
protocol BuiltinPlugin: AnyObject {
    var id: BuiltinPluginID { get }
    func start()
    func stop()
}

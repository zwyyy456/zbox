import Foundation

nonisolated struct ExtensionViewSnapshot: Codable, Sendable {
    var title: String?
    var searchable: Bool?
    var items: [ExtensionListItem]?
    var detail: String?
    var fields: [ExtensionField]?
    var actions: [ExtensionAction]?
    var loading: Bool?
    var message: String?
    var error: String?

    func validate() throws {
        let items = items ?? [], fields = fields ?? [], actions = actions ?? []
        guard items.count <= 1000, fields.count <= 50, actions.count <= 20,
              Set(items.map(\.id)).count == items.count, Set(fields.map(\.id)).count == fields.count,
              Set(actions.map(\.id)).count == actions.count,
              (items.map(\.id) + fields.map(\.id) + actions.map(\.id)).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else {
            throw ExtensionFailure("The extension sent invalid or oversized UI content.")
        }
        var texts: [String] = [title, detail, message, error].compactMap { $0 }
        for item in items { texts += [item.title, item.subtitle ?? ""] }
        for field in fields { texts += [field.name, field.value ?? "", field.error ?? ""]; texts += field.options ?? [] }
        texts += actions.map(\.title)
        guard texts.allSatisfy({ $0.utf8.count <= 1_048_576 }) else { throw ExtensionFailure("UI text exceeds 1 MiB.") }
        for field in fields {
            guard ["text", "multiline", "boolean", "choice"].contains(field.type),
                  field.type != "choice" || (!(field.options ?? []).isEmpty && Set(field.options ?? []).count == field.options?.count) else { throw ExtensionFailure("Unsupported form field.") }
        }
    }
}

nonisolated struct ExtensionListItem: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    var subtitle: String?
}

nonisolated struct ExtensionField: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: String
    var value: String?
    var options: [String]?
    var error: String?
}

nonisolated struct ExtensionAction: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    var enabled: Bool?
    var destructive: Bool?
}

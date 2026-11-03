import Foundation

public nonisolated struct ExtensionViewSnapshot: Codable, Sendable {
    public var title: String?
    public var searchable: Bool?
    public var items: [ExtensionListItem]?
    public var detail: String?
    public var fields: [ExtensionField]?
    public var actions: [ExtensionAction]?
    public var loading: Bool?
    public var message: String?
    public var error: String?

    public init(title: String? = nil, searchable: Bool? = nil, items: [ExtensionListItem]? = nil,
                detail: String? = nil, fields: [ExtensionField]? = nil, actions: [ExtensionAction]? = nil,
                loading: Bool? = nil, message: String? = nil, error: String? = nil) {
        self.title = title; self.searchable = searchable; self.items = items; self.detail = detail
        self.fields = fields; self.actions = actions; self.loading = loading; self.message = message; self.error = error
    }

    public func validate() throws {
        let items = items ?? [], fields = fields ?? [], actions = actions ?? []
        guard items.count <= 1000, fields.count <= 50, actions.count <= 20,
              Set(items.map(\.id)).count == items.count, Set(fields.map(\.id)).count == fields.count,
              Set(actions.map(\.id)).count == actions.count,
              (items.map(\.id) + fields.map(\.id) + actions.map(\.id)).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else {
            throw ExtensionProtocolError("The extension sent invalid or oversized UI content.")
        }
        var texts: [String] = [title, detail, message, error].compactMap { $0 }
        for item in items { texts += [item.title, item.subtitle ?? ""] }
        for field in fields { texts += [field.name, field.value ?? "", field.error ?? ""]; texts += field.options ?? [] }
        texts += actions.map(\.title)
        guard texts.allSatisfy({ $0.utf8.count <= 1_048_576 }) else { throw ExtensionProtocolError("UI text exceeds 1 MiB.") }
        for field in fields {
            guard ["text", "multiline", "boolean", "choice"].contains(field.type),
                  field.type != "choice" || (!(field.options ?? []).isEmpty && Set(field.options ?? []).count == field.options?.count) else { throw ExtensionProtocolError("Unsupported form field.") }
        }
    }
}

public nonisolated struct ExtensionListItem: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public var subtitle: String?
    public init(id: String, title: String, subtitle: String? = nil) { self.id = id; self.title = title; self.subtitle = subtitle }
}

public nonisolated struct ExtensionField: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let type: String
    public var value: String?
    public var options: [String]?
    public var error: String?
    public init(id: String, name: String, type: String, value: String? = nil, options: [String]? = nil, error: String? = nil) {
        self.id = id; self.name = name; self.type = type; self.value = value; self.options = options; self.error = error
    }
}

public nonisolated struct ExtensionAction: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public var enabled: Bool?
    public var destructive: Bool?
    public init(id: String, title: String, enabled: Bool? = nil, destructive: Bool? = nil) {
        self.id = id; self.title = title; self.enabled = enabled; self.destructive = destructive
    }
}

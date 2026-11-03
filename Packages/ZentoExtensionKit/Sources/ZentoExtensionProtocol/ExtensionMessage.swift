import Foundation

public nonisolated enum ExtensionValue: Codable, Sendable, Equatable {
    case null, bool(Bool), integer(Int), number(Double), string(String), array([ExtensionValue]), object([String: ExtensionValue])
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let data = try? value.decode(Bool.self) { self = .bool(data) }
        else if let data = try? value.decode(Int.self) { self = .integer(data) }
        else if let data = try? value.decode(Double.self) { self = .number(data) }
        else if let data = try? value.decode(String.self) { self = .string(data) }
        else if let data = try? value.decode([ExtensionValue].self) { self = .array(data) }
        else { self = .object(try value.decode([String: ExtensionValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let data): try value.encode(data)
        case .integer(let data): try value.encode(data)
        case .number(let data): try value.encode(data)
        case .string(let data): try value.encode(data)
        case .array(let data): try value.encode(data)
        case .object(let data): try value.encode(data)
        }
    }
    public subscript(_ key: String) -> ExtensionValue? { if case .object(let value) = self { value[key] } else { nil } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var int: Int? { if case .integer(let value) = self { value } else { nil } }
    public var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
}

public nonisolated struct ExtensionMessage: Codable, Sendable {
    public var jsonrpc = "2.0"
    public var id: String?
    public var method: String?
    public var params: ExtensionValue?
    public var result: ExtensionValue?
    public var error: ExtensionRPCError?

    public init(id: String? = nil, method: String? = nil, params: ExtensionValue? = nil,
                result: ExtensionValue? = nil, error: ExtensionRPCError? = nil) {
        self.id = id; self.method = method; self.params = params; self.result = result; self.error = error
    }

    public func validate() throws {
        guard jsonrpc == "2.0", id?.isEmpty != true else { throw ExtensionProtocolError("Invalid protocol envelope.") }
        if let method {
            guard !method.isEmpty, result == nil, error == nil else { throw ExtensionProtocolError("Invalid protocol request.") }
        } else {
            guard id != nil, (result != nil) != (error != nil), params == nil else { throw ExtensionProtocolError("Invalid protocol response.") }
        }
    }
}

public nonisolated struct ExtensionRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public init(code: Int, message: String) { self.code = code; self.message = message }
}

extension ExtensionMessage {
    public nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        params = try container.decodeIfPresent(ExtensionValue.self, forKey: .params)
        result = container.contains(.result) ? try container.decode(ExtensionValue.self, forKey: .result) : nil
        error = try container.decodeIfPresent(ExtensionRPCError.self, forKey: .error)
    }
}

public nonisolated struct ExtensionFrameDecoder {
    public static let limit = 8 * 1024 * 1024
    private var buffer = Data()
    public init() {}
    public mutating func append(_ bytes: Data) throws -> [ExtensionMessage] {
        buffer.append(bytes)
        var messages: [ExtensionMessage] = []
        while let newline = buffer.firstIndex(of: 10) {
            let frame = buffer[..<newline]
            guard frame.count <= Self.limit else { throw ExtensionProtocolError("Protocol frame exceeds 8 MiB.") }
            let message = try JSONDecoder().decode(ExtensionMessage.self, from: frame)
            try message.validate()
            messages.append(message)
            buffer.removeSubrange(...newline)
        }
        guard buffer.count <= Self.limit else { throw ExtensionProtocolError("Protocol frame exceeds 8 MiB.") }
        return messages
    }
    public var hasPartialFrame: Bool { !buffer.isEmpty }
}

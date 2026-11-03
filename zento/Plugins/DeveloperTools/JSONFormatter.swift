import Foundation

nonisolated struct JSONSyntaxError: LocalizedError {
    let reason: String
    let line: Int
    let column: Int
    let utf16Offset: Int
    var errorDescription: String? { String(localized: "Line \(line), column \(column): \(reason)") }
}

/// Validates JSON grammar while copying tokens verbatim, including number spelling and duplicate keys.
nonisolated struct JSONFormatter {
    enum Operation: String, CaseIterable, Sendable {
        case format, compact, validate
        var title: String {
            switch self {
            case .format: String(localized: "Format JSON")
            case .compact: String(localized: "Compact")
            case .validate: String(localized: "Validate")
            }
        }
    }

    static func process(_ source: String, operation: Operation, indentation: Int = 2) throws -> String {
        guard source.utf8.count <= 1_048_576 else {
            throw DeveloperToolError(message: String(localized: "Input exceeds the 1 MiB limit."))
        }
        var parser = JSONFormatter(bytes: Array(source.utf8), operation: operation, indentation: indentation)
        try parser.parse()
        return String(decoding: parser.output, as: UTF8.self)
    }

    private let bytes: [UInt8]
    private let operation: Operation
    private let indentation: Int
    private var index = 0
    private var output: [UInt8] = []
    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private enum State {
        case value, end, firstArrayValue, arrayValue, arrayEnd, firstObjectKey, objectKey, objectEnd
    }
    private var states: [State] = [.end, .value]
    private var depth = 0

    private mutating func parse() throws {
        while let state = states.popLast() {
            try Task.checkCancellation()
            skipWhitespace()
            switch state {
            case .value: try value()
            case .end:
                guard index == bytes.count else {
                    throw failure(String(localized: "Unexpected text after the JSON value."))
                }
            case .firstArrayValue where current == 93:
                try closeContainer(93, empty: true)
            case .firstObjectKey where current == 125:
                try closeContainer(125, empty: true)
            case .firstArrayValue, .arrayValue:
                try newline(depth)
                states += [.arrayEnd, .value]
            case .firstObjectKey, .objectKey:
                guard current == 34 else { throw failure(String(localized: "Expected a quoted object key.")) }
                try newline(depth)
                try string()
                skipWhitespace()
                guard current == 58 else { throw failure(String(localized: "Expected ':' after the object key.")) }
                index += 1
                try emit(operation == .format ? [58, 32] : [58])
                states += [.objectEnd, .value]
            case .arrayEnd: try endMember(closing: 93, next: .arrayValue)
            case .objectEnd: try endMember(closing: 125, next: .objectKey)
            }
        }
    }

    private mutating func value() throws {
        guard let byte = current else { throw failure(String(localized: "Expected a JSON value.")) }
        switch byte {
        case 123, 91:
            guard depth < 256 else { throw failure(String(localized: "JSON exceeds the 256-level nesting limit.")) }
            try emit([byte])
            index += 1
            depth += 1
            states.append(byte == 123 ? .firstObjectKey : .firstArrayValue)
        case 34: try string()
        case 116: try literal("true")
        case 102: try literal("false")
        case 110: try literal("null")
        case 45, 48...57: try number()
        default: throw failure(String(localized: "Expected a JSON value."))
        }
    }

    private mutating func closeContainer(_ closing: UInt8, empty: Bool) throws {
        index += 1
        depth -= 1
        if !empty { try newline(depth) }
        try emit([closing])
    }

    private mutating func endMember(closing: UInt8, next: State) throws {
        if current == closing {
            try closeContainer(closing, empty: false)
        } else {
            guard current == 44 else { throw failure(String(localized: "Expected ',' or the closing bracket.")) }
            index += 1
            try emit([44])
            states.append(next)
        }
    }

    private mutating func string() throws {
        let start = index
        index += 1
        while let byte = current {
            if index % 4096 == 0 { try Task.checkCancellation() }
            switch byte {
            case 34:
                index += 1
                try emit(bytes[start..<index])
                return
            case 0..<32: throw failure(String(localized: "Unescaped control character in a string."))
            case 92:
                index += 1
                switch current {
                case 34, 92, 47, 98, 102, 110, 114, 116: index += 1
                case 117:
                    index += 1
                    for _ in 0..<4 {
                        guard let byte = current, (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) else {
                            throw failure(String(localized: "Expected four hexadecimal digits after '\\u'."))
                        }
                        index += 1
                    }
                default: throw failure(String(localized: "Invalid string escape."))
                }
            default: index += 1
            }
        }
        throw failure(String(localized: "Unterminated string."))
    }

    private mutating func number() throws {
        let start = index
        if current == 45 { index += 1 }
        if current == 48 {
            index += 1
        } else {
            guard let byte = current, (49...57).contains(byte) else {
                throw failure(String(localized: "Expected a digit in the number."))
            }
            consumeDigits()
        }
        if current == 46 {
            index += 1
            try requiredDigits()
        }
        if current == 101 || current == 69 {
            index += 1
            if current == 43 || current == 45 { index += 1 }
            try requiredDigits()
        }
        try emit(bytes[start..<index])
    }

    private mutating func requiredDigits() throws {
        guard let byte = current, (48...57).contains(byte) else {
            throw failure(String(localized: "Expected a digit in the number."))
        }
        consumeDigits()
    }

    private mutating func consumeDigits() {
        while let byte = current, (48...57).contains(byte) { index += 1 }
    }

    private mutating func literal(_ literal: String) throws {
        for byte in literal.utf8 {
            guard current == byte else { throw failure(String(localized: "Invalid JSON literal.")) }
            index += 1
        }
        try emit(literal.utf8)
    }

    private mutating func skipWhitespace() {
        while let byte = current, [9, 10, 13, 32].contains(byte) { index += 1 }
    }

    private mutating func newline(_ depth: Int) throws {
        if operation == .format { try emit([10] + Array(repeating: 32, count: depth * indentation)) }
    }

    private mutating func emit(_ token: some Collection<UInt8>) throws {
        guard operation != .validate else { return }
        guard output.count + token.count <= 8 * 1_048_576 else {
            throw DeveloperToolError(message: String(localized: "Formatted output exceeds the 8 MiB limit."))
        }
        output.append(contentsOf: token)
    }

    private func failure(_ reason: String) -> JSONSyntaxError {
        let prefix = String(decoding: bytes.prefix(index), as: UTF8.self)
        var line = 1
        var column = 1
        for character in prefix {
            if character.isNewline { line += 1; column = 1 } else { column += 1 }
        }
        return JSONSyntaxError(reason: reason, line: line, column: column, utf16Offset: prefix.utf16.count)
    }
}

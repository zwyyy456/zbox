import Foundation

nonisolated struct SnippetTemplate {
    private enum Part { case text(String), date, time, clipboard }
    private let parts: [Part]

    init(_ source: String) {
        var parts: [Part] = []
        var literal = ""
        var index = source.startIndex
        while index < source.endIndex {
            let rest = source[index...]
            if rest.hasPrefix("\\{{") {
                literal += "{{"
                index = source.index(index, offsetBy: 3)
                continue
            }
            if rest.hasPrefix("{{"), let end = rest.range(of: "}}") {
                let token = String(source[index..<end.upperBound])
                let part: Part?
                switch token {
                case "{{date}}": part = .date
                case "{{time}}": part = .time
                case "{{clipboard}}": part = .clipboard
                default: part = nil
                }
                if let part {
                    if !literal.isEmpty { parts.append(.text(literal)); literal = "" }
                    parts.append(part)
                } else { literal += token }
                index = end.upperBound
            } else {
                literal.append(source[index])
                index = source.index(after: index)
            }
        }
        if !literal.isEmpty { parts.append(.text(literal)) }
        self.parts = parts
    }

    func render(at date: Date = Date(), timeZone: TimeZone = .current, clipboard: () throws -> String) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let dateText = formatter.string(from: date)
        formatter.dateFormat = "HH:mm"
        let timeText = formatter.string(from: date)
        var clipboardText: String?
        var result = ""
        for part in parts {
            switch part {
            case .text(let text): result += text
            case .date: result += dateText
            case .time: result += timeText
            case .clipboard:
                if clipboardText == nil { clipboardText = try clipboard() }
                result += clipboardText ?? ""
            }
        }
        return result
    }
}

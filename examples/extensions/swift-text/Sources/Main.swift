import Foundation
import ZboxExtensionSDK
import ZboxExtensionProtocol

actor TextPreview {
    var value = "Read selected text to preview the converted result."
    func set(_ text: String) throws { try Task.checkCancellation(); value = text }
}

@main
struct TextCaseExtension {
    static func main() async throws {
        let preview = TextPreview()
        try await ExtensionClient.run { event, api in
            switch event.params["actionID"]?.string {
            case "read":
                let selected = try await api.call("selection.read").string ?? ""
                let converted = event.params["selectedID"]?.string == "lower" ? selected.lowercased() : selected.uppercased()
                try Task.checkCancellation()
                try await preview.set((event.params["values"]?["prefix"]?.string ?? "") + converted)
            case "copy": _ = try await api.call("clipboard.write", params: ["text": .string(await preview.value)])
            default: break
            }
            let query = event.params["query"]?.string?.lowercased() ?? ""
            let items = [ExtensionListItem(id: "upper", title: "Uppercase"), ExtensionListItem(id: "lower", title: "Lowercase")]
            try await api.show(ExtensionViewSnapshot(title: "Text Case · Swift", searchable: true,
                items: items.filter { query.isEmpty || $0.title.lowercased().contains(query) }, detail: await preview.value,
                fields: [ExtensionField(id: "prefix", name: "Prefix", type: "text", value: "")],
                actions: [ExtensionAction(id: "read", title: "Read and Convert Selection"), ExtensionAction(id: "copy", title: "Copy Result")]))
        }
    }
}

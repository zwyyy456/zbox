import SwiftUI

struct ScreenshotEditorView: View {
    let plugin: ScreenshotPlugin
    var body: some View {
        VStack {
            if let image = plugin.image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            }
            if let message = plugin.statusMessage { Text(message).foregroundStyle(.secondary) }
        }.padding()
    }
}

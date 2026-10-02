import SwiftUI

struct ScreenshotEditorView: View {
    @Bindable var plugin: ScreenshotPlugin
    var body: some View {
        VStack(spacing: 0) {
            if let document = plugin.document {
                ScreenshotDocumentView(document: document).disabled(plugin.isExporting || plugin.isUploading)
                Divider()
                HStack {
                    Picker("Format", selection: $plugin.format) {
                        ForEach(ScreenshotFormat.allCases) { Text($0.title).tag($0) }
                    }.frame(width: 130)
                    Spacer()
                    Button("Copy Image", action: plugin.copyImage).keyboardShortcut("c", modifiers: .command)
                    Button("Save…", action: plugin.saveImage).keyboardShortcut("s", modifiers: .command)
                    Button("Upload", action: plugin.uploadImage)
                    Button(plugin.completionTitle, action: plugin.finishEditing).keyboardShortcut(.return, modifiers: .command)
                }.padding().disabled(plugin.isExporting || plugin.isUploading)
            }
            if plugin.isUploading {
                HStack {
                    Text(plugin.uploadHostName).lineLimit(1)
                    ProgressView(value: plugin.uploadProgress)
                    Button("Cancel Upload", action: plugin.cancelUpload)
                }.padding()
            }
            if plugin.canRetryUpload { Button("Retry Last Upload", action: plugin.retryUpload).padding(8) }
            if plugin.uploadedURL != nil { Button("Copy Link", action: plugin.copyUploadedLink).padding(8) }
            if plugin.isExporting { ProgressView().controlSize(.small).padding(8) }
            if let message = plugin.statusMessage {
                Text(message).font(.callout).foregroundStyle(.secondary).padding()
            }
        }
    }
}

private struct ScreenshotDocumentView: View {
    @Bindable var document: ScreenshotDocument
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Tool", selection: $document.tool) {
                    ForEach(ScreenshotTool.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Button(action: document.undo) { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo").accessibilityLabel("Undo").keyboardShortcut("z", modifiers: .command).disabled(!document.canUndo)
                Button(action: document.redo) { Image(systemName: "arrow.uturn.forward") }
                    .help("Redo").accessibilityLabel("Redo").keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!document.canRedo)
            }.padding()
            if document.tool == .text {
                TextField("Enter text, then click the image", text: $document.text).textFieldStyle(.roundedBorder).padding(.horizontal).padding(.bottom, 8)
            }
            ScrollView([.horizontal, .vertical]) {
                ScreenshotCanvas(document: document)
                    .frame(width: document.edit.crop.width * document.zoom, height: document.edit.crop.height * document.zoom)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.08))
            HStack {
                Text("\(Int(document.edit.crop.width)) × \(Int(document.edit.crop.height)) px").monospacedDigit()
                Spacer()
                Button { document.zoom = max(0.05, document.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("Zoom Out")
                Text(document.zoom, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 55)
                Button { document.zoom = min(4, document.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("Zoom In")
            }.font(.caption).padding(8)
        }
    }
}

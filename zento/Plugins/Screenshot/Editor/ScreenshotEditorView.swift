import SwiftUI

struct ScreenshotEditorView: View {
    @Bindable var plugin: ScreenshotPlugin
    var body: some View {
        VStack(spacing: 0) {
            if let document = plugin.document {
                if document.showsText {
                    ScreenshotOCRView(document: document, copy: plugin.copyText)
                } else {
                    ScreenshotDocumentView(document: document, status: plugin.statusMessage, exporting: plugin.isExporting).disabled(plugin.isExporting || plugin.isUploading)
                }

            }
            if plugin.isUploading {
                HStack {
                    Text(plugin.uploadHostName).lineLimit(1)
                    ProgressView(value: plugin.uploadProgress)
                    Button("Cancel Upload", action: plugin.cancelUpload)
                }.padding()
            }
            if plugin.canRetryUpload {
                HStack {
                    Text("Retry uses the previous exported image and its original image host.").font(.caption)
                    Button("Retry Last Upload", action: plugin.retryUpload)
                }.padding(8)
            }
            if plugin.uploadedURL != nil { Button("Copy Link", action: plugin.copyUploadedLink).padding(8) }
            if plugin.needsScreenRecordingPermission {
                Button("Open Screen Recording Settings", action: plugin.openScreenRecordingSettings).padding(8)
            }
            if plugin.document == nil || plugin.document?.showsText == true, let status = plugin.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
    }
}

private struct ScreenshotDocumentView: View {
    @Bindable var document: ScreenshotDocument
    let status: String?
    let exporting: Bool
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ScreenshotCanvas(document: document)
                        .frame(width: document.edit.crop.width * document.zoom, height: document.edit.crop.height * document.zoom)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.08))
            HStack {
                if exporting { ProgressView().controlSize(.mini) }
                if let status {
                    Text(status).lineLimit(1).help(status)
                } else {
                    Text("\(Int(document.edit.crop.width)) × \(Int(document.edit.crop.height)) px").monospacedDigit()
                }
                Spacer()
                Button { document.zoom = max(0.05, document.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("Zoom Out")
                Text(document.zoom, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 55)
                Button { document.zoom = min(4, document.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("Zoom In")
            }.font(.caption).buttonStyle(.borderless).controlSize(.small)
                .padding(.horizontal, 8).frame(height: 28).background(.bar)
        }
    }
}

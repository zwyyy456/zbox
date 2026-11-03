import SwiftUI

struct DisplayHiDPIEditor: View {
    @Environment(\.dismiss) private var dismiss
    let display: DisplayInfo
    let manager: DisplayHiDPIManager
    @State private var width = ""
    @State private var height = ""

    private var configuration: DisplayHiDPIConfiguration? {
        guard let width = Int(width), let height = Int(height) else { return nil }
        return try? DisplayHiDPIConfiguration(vendor: display.vendor, product: display.product,
                                             nativeWidth: width, nativeHeight: height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Additional HiDPI").font(.headline)
            Text(display.name)
            Text("Enter the physical panel's native resolution before rotation, not the current looks-like or rendering size.")
            HStack {
                TextField("Native Width", text: $width)
                Text("×")
                TextField("Native Height", text: $height)
            }
            Text("This requests 2× rendering modes in small scaling steps. It does not change EDID or guarantee that every requested mode is supported.")
                .font(.caption).foregroundStyle(.secondary)
            Text("The override applies to all displays of this vendor and model. Existing overrides will not be overwritten. A restart is required.")
                .font(.caption)
            if let configuration {
                Text("Requested scaling sizes: \(configuration.logicalSizes.count)")
                Text("Logical width range: \(configuration.nativeWidth / 2)–\(configuration.nativeWidth)")
                    .font(.caption)
            } else {
                Text("Enter the panel's native unrotated resolution: width 640–16384 and height 480–16384.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = manager.statusMessage { Text(message).font(.caption) }
            HStack {
                if manager.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.disabled(manager.isBusy)
                Button("Install with Administrator Approval") {
                    guard let configuration else { return }
                    Task {
                        if await manager.install(on: display, configuration: configuration) { dismiss() }
                    }
                }
                .disabled(configuration == nil || manager.isBusy)
            }
        }
        .padding(20).frame(width: 560)
        .interactiveDismissDisabled(manager.isBusy)
        .onAppear { manager.statusMessage = nil }
    }
}

import SwiftUI

@MainActor
@Observable
final class CalculatorPlugin {
    private static let commandID = CommandID("calculator.open")

    var inputRadix: CalculatorEngine.Radix = .decimal
    private(set) var engine = CalculatorEngine()

    @ObservationIgnored
    private var window: NSWindow?

    var decimalText: String { engine.error == nil ? engine.decimalText : String(localized: "Error") }
    var hexadecimalText: String { engine.error == nil ? engine.hexadecimalText : String(localized: "Error") }

    var errorMessage: String? {
        switch engine.error {
        case .divisionByZero: String(localized: "Cannot divide by zero.")
        case .overflow: String(localized: "The result is outside the 64-bit integer range.")
        case nil: nil
        }
    }

    func register(in registry: CommandRegistry) throws {
        let descriptor = CommandDescriptor(
            id: Self.commandID,
            title: String(localized: "Calculator"),
            subtitle: String(localized: "Built-in Calculator"),
            keywords: [
                "calculator", "calculate", "decimal", "hexadecimal", "hex",
                "计算器", "计算", "十进制", "十六进制",
            ]
        )
        try registry.register(descriptor) { [weak self] _ in
            self?.show()
        }
    }

    func systemImage(for commandID: CommandID) -> String? {
        commandID == Self.commandID ? "function" : nil
    }

    func press(_ key: CalculatorEngine.Key) { engine.press(key, radix: inputRadix) }

    func isSelected(_ key: CalculatorEngine.Key) -> Bool { engine.isSelected(key) }

    func stop() { window?.orderOut(nil) }

    private func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let contentView = NSHostingView(
            rootView: CalculatorView(calculator: self) { [weak self] in
                self?.window?.orderOut(nil)
            }
        )
        contentView.frame = NSRect(x: 0, y: 0, width: 420, height: 520)

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.title = String(localized: "Calculator")
        window.minSize = NSSize(width: 360, height: 460)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("builtin-calculator-window")
        window.center()
        return window
    }
}

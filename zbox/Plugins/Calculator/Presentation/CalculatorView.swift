import SwiftUI

struct CalculatorView: View {
    let calculator: CalculatorPlugin
    let close: () -> Void

    @FocusState private var acceptsKeyboardInput: Bool

    var body: some View {
        @Bindable var calculator = calculator

        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Input Base", selection: $calculator.inputRadix) {
                    ForEach(CalculatorEngine.Radix.allCases, id: \.self) { radix in
                        Text(radix.shortTitle)
                            .tag(radix)
                            .accessibilityLabel(radix.accessibilityLabel)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent {
                    result(calculator.decimalText, label: String(localized: "Decimal value"))
                } label: {
                    Text("DEC").font(.headline.monospaced())
                }

                Divider()

                LabeledContent {
                    result(calculator.hexadecimalText, label: String(localized: "Hexadecimal value"))
                } label: {
                    Text("HEX").font(.headline.monospaced())
                }

                if let message = calculator.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding()
            .background(.quaternary, in: .rect(cornerRadius: 12))

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(CalculatorEngine.Key.rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { key in
                            Button {
                                calculator.press(key)
                            } label: {
                                Group {
                                    if key == .backspace {
                                        Label("Backspace", systemImage: "delete.backward")
                                            .labelStyle(.iconOnly)
                                    } else {
                                        Text(key.title)
                                            .font(.title3.monospaced())
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(tint(for: key))
                            .disabled(key.isEnabled(for: calculator.inputRadix) == false)
                            .accessibilityLabel(key.accessibilityLabel)
                            .accessibilityValue(
                                calculator.isSelected(key) ? String(localized: "Selected") : ""
                            )
                            .overlay(alignment: .topTrailing) {
                                if calculator.isSelected(key) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .padding(4)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 360, idealWidth: 420, minHeight: 460, idealHeight: 520)
        .focusable()
        .focused($acceptsKeyboardInput)
        .onAppear { acceptsKeyboardInput = true }
        .onKeyPress(phases: .down, action: handleKeyPress)
        .onDeleteCommand { calculator.press(.backspace) }
        .onExitCommand(perform: close)
    }

    private func result(_ value: String, label: String) -> some View {
        Text(value)
            .font(.title2.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .textSelection(.enabled)
            .accessibilityLabel(label)
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.intersection([.command, .control, .option]).isEmpty,
              let key = CalculatorEngine.Key(character: press.characters.lowercased().first) else {
            return .ignored
        }
        calculator.press(key)
        return .handled
    }

    private func tint(for key: CalculatorEngine.Key) -> Color {
        switch key {
        case .equals:
            .accentColor
        case .operation:
            calculator.isSelected(key) ? .accentColor : .secondary
        default:
            .secondary.opacity(0.35)
        }
    }
}

extension CalculatorEngine.Radix {
    var shortTitle: String { self == .decimal ? "DEC" : "HEX" }

    var accessibilityLabel: String {
        switch self {
        case .decimal: String(localized: "Decimal")
        case .hexadecimal: String(localized: "Hexadecimal")
        }
    }
}

extension CalculatorEngine.Key {
    static let rows: [[Self]] = [
        [.digit(10), .digit(11), .digit(12), .digit(13)],
        [.digit(14), .digit(15), .toggleSign, .operation(.divide)],
        [.digit(7), .digit(8), .digit(9), .operation(.multiply)],
        [.digit(4), .digit(5), .digit(6), .operation(.subtract)],
        [.digit(1), .digit(2), .digit(3), .operation(.add)],
        [.clear, .digit(0), .backspace, .equals],
    ]

    init?(character: Character?) {
        guard let character else { return nil }
        if let digit = Int(String(character), radix: 16) {
            self = .digit(digit)
            return
        }
        switch character {
        case "+": self = .operation(.add)
        case "-", "−": self = .operation(.subtract)
        case "*", "x", "×": self = .operation(.multiply)
        case "/", "÷": self = .operation(.divide)
        case "\r", "\n", "=": self = .equals
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .digit(let digit): String(digit, radix: 16, uppercase: true)
        case .operation(let operation): operation.rawValue
        case .toggleSign: "±"
        case .backspace: "⌫"
        case .clear: "AC"
        case .equals: "="
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .digit, .operation: title
        case .toggleSign: String(localized: "Change Sign")
        case .backspace: String(localized: "Backspace")
        case .clear: String(localized: "All Clear")
        case .equals: String(localized: "Equals")
        }
    }

    func isEnabled(for radix: CalculatorEngine.Radix) -> Bool {
        if case .digit(let digit) = self {
            digit < radix.rawValue
        } else {
            true
        }
    }
}

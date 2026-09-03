nonisolated struct CalculatorEngine: Sendable {
    enum Radix: Int, CaseIterable, Hashable, Sendable {
        case decimal = 10
        case hexadecimal = 16
    }

    enum Operation: String, Hashable, Sendable {
        case add = "+"
        case subtract = "−"
        case multiply = "×"
        case divide = "÷"
    }

    enum Key: Hashable, Sendable {
        case digit(Int)
        case operation(Operation)
        case toggleSign, backspace, clear, equals
    }

    enum Failure: Equatable, Sendable {
        case divisionByZero, overflow
    }

    private(set) var currentValue: Int64 = 0
    private(set) var pendingOperation: Operation?
    private(set) var error: Failure?
    private var storedValue: Int64?
    private var isEnteringValue = false

    var decimalText: String { String(currentValue) }
    var hexadecimalText: String {
        String(UInt64(bitPattern: currentValue), radix: 16, uppercase: true)
    }

    mutating func press(_ key: Key, radix: Radix) {
        switch key {
        case .digit(let digit): input(digit, radix: radix)
        case .operation(let operation): choose(operation)
        case .toggleSign: toggleSign()
        case .backspace: deleteLastDigit(radix: radix)
        case .clear: reset()
        case .equals: calculateResult()
        }
    }

    func isSelected(_ key: Key) -> Bool {
        guard case .operation(let operation) = key else { return false }
        return pendingOperation == operation && isEnteringValue == false
    }

    private mutating func input(_ digit: Int, radix: Radix) {
        guard (0..<radix.rawValue).contains(digit) else { return }
        if error != nil { reset() }

        let currentText = radix == .decimal ? decimalText : hexadecimalText
        let text = (isEnteringValue ? currentText : "")
            + String(digit, radix: 16, uppercase: true)
        let value = radix == .decimal
            ? Int64(text, radix: 10)
            : UInt64(text, radix: 16).map { Int64(bitPattern: $0) }
        guard let value else {
            reset(error: .overflow)
            return
        }
        currentValue = value
        isEnteringValue = true
    }

    private mutating func choose(_ operation: Operation) {
        guard error == nil else { return }
        if pendingOperation != nil, isEnteringValue {
            guard resolvePendingOperation() else { return }
        } else if storedValue == nil {
            storedValue = currentValue
        }
        pendingOperation = operation
        isEnteringValue = false
    }

    private mutating func calculateResult() {
        guard error == nil, pendingOperation != nil,
              storedValue != nil, isEnteringValue,
              resolvePendingOperation() else { return }
        storedValue = nil
        pendingOperation = nil
    }

    private mutating func resolvePendingOperation() -> Bool {
        guard let storedValue, let pendingOperation else { return false }
        if pendingOperation == .divide, currentValue == 0 {
            reset(error: .divisionByZero)
            return false
        }

        let result = switch pendingOperation {
        case .add: storedValue.addingReportingOverflow(currentValue)
        case .subtract: storedValue.subtractingReportingOverflow(currentValue)
        case .multiply: storedValue.multipliedReportingOverflow(by: currentValue)
        case .divide: storedValue.dividedReportingOverflow(by: currentValue)
        }
        guard result.overflow == false else {
            reset(error: .overflow)
            return false
        }
        currentValue = result.partialValue
        self.storedValue = currentValue
        isEnteringValue = false
        return true
    }

    private mutating func toggleSign() {
        guard error == nil else { return }
        let result = currentValue.multipliedReportingOverflow(by: -1)
        guard result.overflow == false else {
            reset(error: .overflow)
            return
        }
        currentValue = result.partialValue
    }

    private mutating func deleteLastDigit(radix: Radix) {
        guard error == nil, isEnteringValue else { return }
        if radix == .decimal {
            currentValue /= 10
        } else {
            currentValue = Int64(bitPattern: UInt64(bitPattern: currentValue) / 16)
        }
    }

    private mutating func reset(error: Failure? = nil) {
        currentValue = 0
        pendingOperation = nil
        storedValue = nil
        self.error = error
        isEnteringValue = false
    }
}

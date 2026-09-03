import Testing
@testable import zbox

struct CalculatorEngineTests {
    @Test
    func keepsDecimalAndHexadecimalRepresentationsInSync() {
        var engine = CalculatorEngine()

        engine.press(.digit(2), radix: .decimal)
        engine.press(.digit(5), radix: .decimal)
        engine.press(.digit(5), radix: .decimal)

        #expect(engine.decimalText == "255")
        #expect(engine.hexadecimalText == "FF")
    }

    @Test
    func acceptsHexadecimalInputAndUsesSigned64BitRepresentation() {
        var engine = CalculatorEngine()

        for _ in 0..<16 {
            engine.press(.digit(15), radix: .hexadecimal)
        }

        #expect(engine.currentValue == -1)
        #expect(engine.decimalText == "-1")
        #expect(engine.hexadecimalText == "FFFFFFFFFFFFFFFF")
    }

    @Test
    func switchingRadixUsesTheCurrentValueAsTheNextInputPrefix() {
        var engine = CalculatorEngine()

        engine.press(.digit(1), radix: .decimal)
        engine.press(.digit(5), radix: .decimal)
        engine.press(.digit(10), radix: .hexadecimal)

        #expect(engine.decimalText == "250")
        #expect(engine.hexadecimalText == "FA")
    }

    @Test
    func evaluatesChainedIntegerArithmetic() {
        var engine = CalculatorEngine()

        engine.press(.digit(1), radix: .decimal)
        engine.press(.digit(2), radix: .decimal)
        engine.press(.operation(.add), radix: .decimal)
        engine.press(.digit(4), radix: .decimal)
        engine.press(.operation(.multiply), radix: .decimal)
        engine.press(.digit(3), radix: .decimal)
        engine.press(.equals, radix: .decimal)

        #expect(engine.currentValue == 48)
        #expect(engine.pendingOperation == nil)
    }

    @Test
    func reportsDivisionByZeroAndClearsOnNewInput() {
        var engine = CalculatorEngine()

        engine.press(.digit(8), radix: .decimal)
        engine.press(.operation(.divide), radix: .decimal)
        engine.press(.digit(0), radix: .decimal)
        engine.press(.equals, radix: .decimal)
        #expect(engine.error == .divisionByZero)

        engine.press(.digit(7), radix: .decimal)
        #expect(engine.error == nil)
        #expect(engine.currentValue == 7)
    }

    @Test
    func reportsDecimalInputOverflow() {
        var engine = CalculatorEngine()

        for character in "9223372036854775808" {
            engine.press(.digit(character.wholeNumberValue ?? 0), radix: .decimal)
        }

        #expect(engine.error == .overflow)
    }
}

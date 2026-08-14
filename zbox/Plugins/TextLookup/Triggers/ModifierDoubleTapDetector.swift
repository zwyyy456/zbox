import Foundation

nonisolated struct ModifierDoubleTapDetector: Sendable {
    private struct CompletedTap: Sendable {
        let keyCode: UInt16
        let timestamp: TimeInterval
    }

    private let maximumInterval: TimeInterval
    private var pressedKeyCode: UInt16?
    private var lastTap: CompletedTap?

    init(maximumInterval: TimeInterval = 0.35) {
        self.maximumInterval = maximumInterval
    }

    mutating func flagsChanged(
        keyCode: UInt16,
        optionIsDown: Bool,
        hasOtherModifiers: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        guard keyCode == 58 || keyCode == 61, !hasOtherModifiers else {
            reset()
            return false
        }

        if optionIsDown {
            guard pressedKeyCode == nil else {
                reset()
                return false
            }
            pressedKeyCode = keyCode
            return false
        }

        guard pressedKeyCode == keyCode else {
            reset()
            return false
        }
        pressedKeyCode = nil

        if let lastTap,
           lastTap.keyCode == keyCode,
           timestamp - lastTap.timestamp <= maximumInterval {
            self.lastTap = nil
            return true
        }

        lastTap = CompletedTap(keyCode: keyCode, timestamp: timestamp)
        return false
    }

    mutating func ordinaryKeyPressed() {
        reset()
    }

    mutating func reset() {
        pressedKeyCode = nil
        lastTap = nil
    }
}

import AppKit
import CoreGraphics

@MainActor
enum ClipboardPasteController {
    static func activate(_ target: NSRunningApplication) async throws {
        guard !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw ClipboardPasteError.targetUnavailable
        }
        let previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard previousPID == target.processIdentifier || previousPID == ProcessInfo.processInfo.processIdentifier else {
            throw ClipboardPasteError.targetUnavailable
        }
        guard target.activate() else { throw ClipboardPasteError.targetUnavailable }
        for _ in 0..<20 {
            try Task.checkCancellation()
            let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if currentPID == target.processIdentifier, !target.isTerminated { return }
            guard currentPID == previousPID || currentPID == ProcessInfo.processInfo.processIdentifier else {
                throw ClipboardPasteError.targetUnavailable
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ClipboardPasteError.targetUnavailable
    }

    static func paste(into target: NSRunningApplication) throws {
        guard !target.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            throw ClipboardPasteError.targetUnavailable
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            throw ClipboardPasteError.targetUnavailable
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

nonisolated enum ClipboardPasteError: LocalizedError {
    case targetUnavailable, permissionRequired
    var errorDescription: String? {
        switch self {
        case .targetUnavailable: String(localized: "The original app is unavailable or has changed. Copy the item and paste it manually.")
        case .permissionRequired: String(localized: "Direct paste requires Accessibility. You can still copy the item.")
        }
    }
}

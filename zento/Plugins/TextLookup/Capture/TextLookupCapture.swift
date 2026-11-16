import CoreGraphics
import Foundation

nonisolated struct TextLookupCapture: Sendable {
    let id: UUID
    let term: String
    let sentence: String?
    let sourceURL: URL?
    let anchorRect: CGRect?
    var isContextFragment = false

    var needsContext: Bool {
        guard let sentence else { return true }
        return sentence.trimmingCharacters(in: .whitespacesAndNewlines) == term
    }
}

nonisolated enum TextCaptureIntent: Sendable {
    case currentSelection
    case pointerLocation(CGPoint)

    var allowsClipboardFallback: Bool {
        if case .currentSelection = self { true } else { false }
    }

    var anchorPoint: CGPoint? {
        if case .pointerLocation(let point) = self { point } else { nil }
    }
}

nonisolated struct TextCaptureRequest: Sendable {
    let id: UUID
    let intent: TextCaptureIntent
    let targetApplicationPID: pid_t
    let excludedApplicationPIDs: Set<pid_t>
    let primaryScreenMaxY: CGFloat
    let triggerAnchorPoint: CGPoint

    var triggerAnchorRect: CGRect {
        CGRect(x: triggerAnchorPoint.x, y: triggerAnchorPoint.y, width: 1, height: 1)
    }
}

nonisolated enum TextCaptureError: LocalizedError, Equatable, Sendable {
    case permissionRequired
    case excludedApplication
    case secureText
    case noSelection
    case noTextAtPointer
    case unsupportedElement
    case selectionTooLong
    case unableToReadText
    case clipboardFallbackFailed
    case screenCapturePermissionRequired

    var allowsCompatibilityFallback: Bool {
        switch self {
        case .noSelection, .noTextAtPointer, .unsupportedElement, .unableToReadText, .clipboardFallbackFailed: true
        default: false
        }
    }

    var allowsClipboardFallback: Bool {
        switch self {
        case .noSelection, .unableToReadText:
            true
        default:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .screenCapturePermissionRequired:
            String(localized: "Local OCR requires Screen Recording permission. Enable it in Text Lookup settings.")
        case .permissionRequired:
            String(localized: "Accessibility permission is required to read text in other apps.")
        case .excludedApplication:
            String(localized: "Text Lookup is disabled for this application.")
        case .secureText:
            String(localized: "Protected text cannot be read.")
        case .noSelection:
            String(localized: "Select a word or phrase first.")
        case .noTextAtPointer:
            String(localized: "Move the pointer over a readable word.")
        case .unsupportedElement:
            String(localized: "Unable to locate a readable word at this position using Accessibility.")
        case .selectionTooLong:
            String(localized: "Select no more than 80 characters and 8 words.")
        case .unableToReadText:
            String(localized: "The selected text could not be read.")
        case .clipboardFallbackFailed:
            String(localized: "The selection could not be read using clipboard compatibility mode.")
        }
    }
}

nonisolated protocol TextCapturing: Sendable {
    func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture
}

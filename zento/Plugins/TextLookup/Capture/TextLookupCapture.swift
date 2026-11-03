import CoreGraphics
import Foundation

nonisolated struct TextLookupCapture: Sendable {
    let id: UUID
    let term: String
    let sentence: String?
    let sourceURL: URL?
    let anchorRect: CGRect?
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

nonisolated struct TextLookupSelectionCandidate: Sendable {
    private static let maximumAge: TimeInterval = 3

    let capture: TextLookupCapture
    let targetApplicationPID: pid_t
    let createdAt: Date

    func isValid(
        at date: Date,
        frontmostApplicationPID: pid_t?
    ) -> Bool {
        frontmostApplicationPID == targetApplicationPID
            && date.timeIntervalSince(createdAt) <= Self.maximumAge
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
            String(localized: "This application does not expose text at this location.")
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

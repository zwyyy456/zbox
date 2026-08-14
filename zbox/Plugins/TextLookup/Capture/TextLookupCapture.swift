import CoreGraphics
import Foundation

nonisolated struct TextLookupCapture: Sendable, Equatable {
    let id: UUID
    let term: String
    let sentence: String?
    let sourceURL: URL?
    let anchorRect: CGRect?
    let sourceApplicationBundleIdentifier: String?
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
    let targetApplicationBundleIdentifier: String?
    let applicationBundleIdentifiersByPID: [pid_t: String]
    let excludedApplicationBundleIdentifiers: Set<String>
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

    var errorDescription: String? {
        switch self {
        case .permissionRequired: "Accessibility permission is required to read text in other apps."
        case .excludedApplication: "Text Lookup is disabled for this application."
        case .secureText: "Protected text cannot be read."
        case .noSelection: "Select a word or phrase first."
        case .noTextAtPointer: "Move the pointer over a readable word."
        case .unsupportedElement: "This application does not expose text at this location."
        case .selectionTooLong: "Select no more than 80 characters and 8 words."
        case .unableToReadText: "The selected text could not be read."
        case .clipboardFallbackFailed: "The selection could not be read using clipboard compatibility mode."
        }
    }
}

nonisolated protocol TextCapturing: Sendable {
    func capture(_ request: TextCaptureRequest) async throws -> TextLookupCapture
}

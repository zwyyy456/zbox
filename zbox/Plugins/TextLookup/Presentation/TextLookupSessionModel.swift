import Foundation
import Observation

@MainActor
@Observable
final class TextLookupSessionModel {
    private(set) var capture: TextLookupCapture?
    private(set) var captureError: TextCaptureError?

    var activeSessionID: UUID? { capture?.id }

    func beginLookup(with capture: TextLookupCapture) {
        self.capture = capture
        captureError = nil
    }

    func present(_ error: TextCaptureError) {
        capture = nil
        captureError = error
    }

    func accepts(_ sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }

    func clear() {
        capture = nil
        captureError = nil
    }
}

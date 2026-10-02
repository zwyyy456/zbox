import AppKit

/// Coordinates temporary clipboard use with history recording inside this process.
@MainActor
final class ClipboardAccessCoordinator {
    private(set) var revision = 0
    private(set) var temporaryAccessCount = 0
    private(set) var ignoredChangeCount: Int?

    func beginTemporaryAccess() {
        temporaryAccessCount += 1
        revision += 1
    }

    func endTemporaryAccess() {
        temporaryAccessCount -= 1
        revision += 1
    }

    func didWrite(changeCount: Int) {
        ignoredChangeCount = changeCount
        revision += 1
    }
}

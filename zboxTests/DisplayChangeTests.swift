import Foundation
import Testing
@testable import zbox

@MainActor
struct DisplayChangeTests {
    @Test func trialAndConfirmationUseDifferentPersistenceAndRevertRestoresOriginal() throws {
        let controller = TestDisplayController()
        let change = DisplayChange(controller: controller)
        try change.begin([controller.selection(controller.alternate)])
        #expect(controller.calls == [false])
        change.revert()
        #expect(controller.current == controller.original)
        #expect(change.pending == nil)
        try change.begin([controller.selection(controller.alternate)])
        change.keep()
        #expect(controller.calls.last == true)
        #expect(controller.current == controller.alternate)
        #expect(change.pending == nil)
    }

    @Test func failedRecoveryKeepsOriginalAndBlocksAnotherChangeUntilRetry() throws {
        let controller = TestDisplayController()
        let change = DisplayChange(controller: controller)
        try change.begin([controller.selection(controller.alternate)])
        controller.fail = true
        change.revert()
        #expect(change.recoveryFailed)
        #expect(change.pending?.original.first?.mode == controller.original)
        #expect(throws: DisplayError.self) { try change.begin([controller.selection(controller.original)]) }
        controller.fail = false
        change.revert()
        #expect(change.pending == nil)
        #expect(controller.current == controller.original)
    }

    @Test func expiredConfirmationRevertsWithoutPersisting() throws {
        let controller = TestDisplayController()
        let change = DisplayChange(controller: controller)
        try change.begin([controller.selection(controller.alternate)])
        change.checkDeadline(at: .distantFuture)
        #expect(controller.current == controller.original)
        #expect(controller.calls == [false, false])
        #expect(change.pending == nil)
    }

    @Test func unavailableModeDoesNotTouchConfiguration() {
        let controller = TestDisplayController()
        let change = DisplayChange(controller: controller)
        let invalid = DisplayModeSpec(width: 1, height: 1, pixelWidth: 1, pixelHeight: 1, refreshMillihertz: 1)
        #expect(throws: DisplayError.self) { try change.begin([controller.selection(invalid)]) }
        #expect(controller.calls.isEmpty)
        #expect(change.pending == nil)
    }
}

@MainActor
private final class TestDisplayController: DisplayConfiguring {
    let original = DisplayModeSpec(width: 1280, height: 720, pixelWidth: 2560, pixelHeight: 1440, refreshMillihertz: 60000)
    let alternate = DisplayModeSpec(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshMillihertz: 60000)
    var current: DisplayModeSpec
    var fail = false
    var calls: [Bool] = []
    init() { current = original }
    func selection(_ mode: DisplayModeSpec) -> DisplaySelection { DisplaySelection(displayID: "test", displayName: "Test", mode: mode) }
    func read() -> [DisplayInfo] {
        [DisplayInfo(id: "test", name: "Test", isBuiltIn: false, vendor: 1, product: 2, rotation: 0,
                     current: current, modes: [original, alternate])]
    }
    func apply(_ selections: [DisplaySelection], permanent: Bool) throws {
        calls.append(permanent)
        if fail { throw DisplayError.unavailable }
        current = selections[0].mode
    }
}

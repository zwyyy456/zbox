import Foundation
import Observation

@MainActor
@Observable
final class DisplayChange {
    struct Pending {
        let original: [DisplaySelection]
        let requested: [DisplaySelection]
        let deadline: Date
    }

    private let controller: any DisplayConfiguring
    private(set) var pending: Pending?
    private(set) var remainingSeconds = 0
    private(set) var recoveryFailed = false
    var errorMessage: String?
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(controller: any DisplayConfiguring) { self.controller = controller }

    func begin(_ selections: [DisplaySelection]) throws {
        guard pending == nil else { throw DisplayError.busy }
        let displays = controller.read()
        let original = try selections.map { selection in
            let matches = displays.filter { $0.id == selection.displayID }
            guard matches.count == 1, let display = matches.first else { throw DisplayError.unavailable }
            guard display.modes.contains(selection.mode) else { throw DisplayError.modeUnavailable }
            return DisplaySelection(displayID: display.id, displayName: display.name, mode: display.current)
        }
        guard !selections.isEmpty else { throw DisplayError.unavailable }
        pending = Pending(original: original, requested: selections, deadline: Date().addingTimeInterval(15))
        remainingSeconds = 15
        recoveryFailed = false
        errorMessage = nil
        do {
            try controller.apply(selections, permanent: false)
        } catch {
            let failure = error.localizedDescription
            revert()
            errorMessage = recoveryFailed ? "\(failure)\n\(errorMessage ?? "")" : failure
            throw error
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, pending != nil else { return }
                checkDeadline()
            }
        }
    }

    func checkDeadline(at now: Date = Date()) {
        guard let pending, !recoveryFailed else { return }
        remainingSeconds = max(0, Int(ceil(pending.deadline.timeIntervalSince(now))))
        if remainingSeconds == 0 { revert() }
    }

    func keep() {
        guard let pending, !recoveryFailed else { return }
        guard pending.deadline > Date() else { revert(); return }
        do {
            let displays = controller.read()
            guard pending.requested.allSatisfy({ selection in
                let matches = displays.filter { $0.id == selection.displayID }
                return matches.count == 1 && matches.first?.current == selection.mode
            }) else { throw DisplayError.modeUnavailable }
            try controller.apply(pending.requested, permanent: true)
            finish()
        } catch {
            let failure = error.localizedDescription
            revert()
            errorMessage = recoveryFailed ? "\(failure)\n\(errorMessage ?? "")" : failure
        }
    }

    func revert() {
        guard let pending else { return }
        timer?.cancel()
        timer = nil
        do {
            try controller.apply(pending.original, permanent: false)
            finish()
        } catch {
            recoveryFailed = true
            remainingSeconds = 0
            errorMessage = String(localized: "Could not restore the previous display configuration. Reconnect missing displays and retry. ") + error.localizedDescription
        }
    }

    private func finish() {
        timer?.cancel()
        timer = nil
        pending = nil
        remainingSeconds = 0
        recoveryFailed = false
        errorMessage = nil
    }
}

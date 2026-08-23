@preconcurrency import Carbon.HIToolbox
import Foundation

enum GlobalHotkeyError: LocalizedError {
    case duplicateRegistration(String)
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(String, OSStatus)
    case replacementRollbackFailed(update: String, rollback: String)

    var errorDescription: String? {
        switch self {
        case .duplicateRegistration(let id):
            "The hotkey registration \(id) already exists."
        case .eventHandlerInstallationFailed(let status):
            "Unable to install the global hotkey handler (\(status))."
        case .registrationFailed(let label, let status):
            "\(label) is already used by another app or could not be registered (\(status))."
        case .replacementRollbackFailed(let update, let rollback):
            "The shortcut update failed (\(update)), and the previous shortcuts could not be restored (\(rollback))."
        }
    }
}

@MainActor
struct HotkeyRegistrationRequest {
    let id: String
    let hotkey: Hotkey
    let label: String
    let action: () -> Void
}

@MainActor
protocol HotkeyRegistering: AnyObject {
    func replace(ids: Set<String>, with requests: [HotkeyRegistrationRequest]) throws
    func unregisterAll()
    func unregister(id: String)
}

@MainActor
final class GlobalHotkeyRegistrar: HotkeyRegistering {
    private static let signature: OSType = 0x5A42584B

    private struct Registration {
        let reference: EventHotKeyRef
        let numericID: UInt32
        let request: HotkeyRegistrationRequest
    }

    private var eventHandler: EventHandlerRef?
    private var registrations: [String: Registration] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextNumericID: UInt32 = 1

    func replace(
        ids: Set<String>,
        with requests: [HotkeyRegistrationRequest]
    ) throws {
        let previous = ids.compactMap { registrations[$0]?.request }
        for id in ids { unregister(id: id) }

        do {
            for request in requests { try register(request) }
        } catch {
            let updateError = error
            for request in requests { unregister(id: request.id) }
            do {
                for request in previous { try register(request) }
            } catch {
                throw GlobalHotkeyError.replacementRollbackFailed(
                    update: updateError.localizedDescription,
                    rollback: error.localizedDescription
                )
            }
            throw updateError
        }
    }

    private func register(_ request: HotkeyRegistrationRequest) throws {
        let id = request.id
        guard registrations[id] == nil else {
            throw GlobalHotkeyError.duplicateRegistration(id)
        }
        try installEventHandlerIfNeeded()

        let numericID = nextNumericID
        nextNumericID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: numericID)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            request.hotkey.keyCode,
            request.hotkey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            throw GlobalHotkeyError.registrationFailed(request.label, status)
        }

        registrations[id] = Registration(
            reference: reference,
            numericID: numericID,
            request: request
        )
        actions[numericID] = request.action
    }

    func unregisterAll() {
        for registration in registrations.values { UnregisterEventHotKey(registration.reference) }
        registrations.removeAll()
        actions.removeAll()
        nextNumericID = 1

        removeEventHandlerIfUnused()
    }

    func unregister(id: String) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.reference)
        actions.removeValue(forKey: registration.numericID)
        removeEventHandlerIfUnused()
    }

    private func removeEventHandlerIfUnused() {
        guard registrations.isEmpty else { return }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let registrar = Unmanaged<GlobalHotkeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return MainActor.assumeIsolated {
                    registrar.handle(event)
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            throw GlobalHotkeyError.eventHandlerInstallationFailed(status)
        }
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == Self.signature,
              let action = actions[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        action()
        return noErr
    }

    isolated deinit {
        unregisterAll()
    }
}

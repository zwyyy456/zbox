@preconcurrency import Carbon.HIToolbox
import Foundation

enum GlobalHotkeyError: LocalizedError {
    case duplicateRegistration(String)
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicateRegistration(let id):
            "The hotkey registration \(id) already exists."
        case .eventHandlerInstallationFailed(let status):
            "Unable to install the global hotkey handler (\(status))."
        case .registrationFailed(let label, let status):
            "\(label) is already used by another app or could not be registered (\(status))."
        }
    }
}

@MainActor
final class GlobalHotkeyRegistrar {
    private static let signature: OSType = 0x5A42584B

    private struct Registration {
        let reference: EventHotKeyRef
        let numericID: UInt32
    }

    private var eventHandler: EventHandlerRef?
    private var registrations: [String: Registration] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextNumericID: UInt32 = 1

    func register(
        id: String,
        hotkey: Hotkey,
        label: String,
        action: @escaping () -> Void
    ) throws {
        guard registrations[id] == nil else {
            throw GlobalHotkeyError.duplicateRegistration(id)
        }
        try installEventHandlerIfNeeded()

        let numericID = nextNumericID
        nextNumericID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: numericID)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            throw GlobalHotkeyError.registrationFailed(label, status)
        }

        registrations[id] = Registration(reference: reference, numericID: numericID)
        actions[numericID] = action
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

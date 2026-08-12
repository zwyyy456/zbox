@preconcurrency import Carbon.HIToolbox
import Foundation

enum GlobalHotkeyError: LocalizedError {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallationFailed(let status):
            "Unable to install the global hotkey handler (\(status))."
        case .registrationFailed(let status):
            "Control-Option-Space is already in use or could not be registered (\(status))."
        }
    }
}

@MainActor
final class GlobalHotkeyRegistrar {
    private static let signature: OSType = 0x5A42584B
    private static let identifier: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var eventHotKey: EventHotKeyRef?
    private var action: (() -> Void)?

    func registerDefault(action: @escaping () -> Void) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
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

        guard handlerStatus == noErr else {
            self.action = nil
            throw GlobalHotkeyError.eventHandlerInstallationFailed(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )

        guard registrationStatus == noErr else {
            unregister()
            throw GlobalHotkeyError.registrationFailed(registrationStatus)
        }
    }

    func unregister() {
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
            self.eventHotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        action = nil
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

        guard status == noErr,
              hotKeyID.signature == Self.signature,
              hotKeyID.id == Self.identifier else {
            return OSStatus(eventNotHandledErr)
        }

        action?()
        return noErr
    }

    isolated deinit {
        unregister()
    }
}

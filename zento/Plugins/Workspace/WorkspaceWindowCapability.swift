import ApplicationServices
import Foundation

nonisolated enum WorkspaceWindowCapability: Equatable {
    case writable, readOnly, unavailable

    init(result: AXError, settable: Bool) {
        self = result == .success ? (settable ? .writable : .readOnly) : .unavailable
    }

    static func exclusion(position: Self, size: Self) -> String? {
        switch position {
        case .readOnly: return String(localized: "This window cannot be moved")
        case .unavailable: return String(localized: "Could not check whether this window can be moved. Try capturing again.")
        case .writable: break
        }
        switch size {
        case .readOnly: return String(localized: "This window cannot be resized")
        case .unavailable: return String(localized: "Could not check whether this window can be resized. Try capturing again.")
        case .writable: return nil
        }
    }

    @MainActor static func read(_ attribute: String, of window: AXUIElement) -> Self {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(window, attribute as CFString, &settable)
        return Self(result: result, settable: settable.boolValue)
    }
}

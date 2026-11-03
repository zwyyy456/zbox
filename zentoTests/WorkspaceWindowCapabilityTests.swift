import ApplicationServices
import Testing
@testable import zento

struct WorkspaceWindowCapabilityTests {
    @Test func distinguishesReadOnlyAttributesFromFailedQueries() {
        #expect(WorkspaceWindowCapability(result: .success, settable: true) == .writable)
        #expect(WorkspaceWindowCapability(result: .success, settable: false) == .readOnly)
        for error in [AXError.cannotComplete, .apiDisabled, .attributeUnsupported, .invalidUIElement] {
            // The out parameter is not evidence of a capability when AX returns an error.
            #expect(WorkspaceWindowCapability(result: error, settable: false) == .unavailable)
            #expect(WorkspaceWindowCapability(result: error, settable: true) == .unavailable)
        }
    }

    @Test func reportsSpecificCapabilityInsteadOfBlamingApplication() {
        let move = WorkspaceWindowCapability.exclusion(position: .readOnly, size: .writable)
        let resize = WorkspaceWindowCapability.exclusion(position: .writable, size: .readOnly)
        let unknownMove = WorkspaceWindowCapability.exclusion(position: .unavailable, size: .writable)
        let unknownSize = WorkspaceWindowCapability.exclusion(position: .writable, size: .unavailable)
        #expect(move != nil && resize != nil && move != resize)
        #expect(unknownMove != nil && unknownMove != move)
        #expect(unknownSize != nil && unknownSize != resize)
        #expect(WorkspaceWindowCapability.exclusion(position: .writable, size: .writable) == nil)
    }
}

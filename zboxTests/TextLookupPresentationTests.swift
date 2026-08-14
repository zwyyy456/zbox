import CoreGraphics
import Foundation
import Testing
@testable import zbox

struct TextLookupPresentationTests {
    @Test
    func placesPanelBelowThenFallsBackAboveAndClampsHorizontally() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let size = CGSize(width: 520, height: 260)

        let below = TextLookupPanelPlacement.origin(
            anchor: CGRect(x: 20, y: 600, width: 40, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        #expect(below == CGPoint(x: 12, y: 332))

        let above = TextLookupPanelPlacement.origin(
            anchor: CGRect(x: 900, y: 30, width: 20, height: 20),
            panelSize: size,
            visibleFrame: visibleFrame
        )
        #expect(above == CGPoint(x: 468, y: 58))
    }

    @Test @MainActor
    func sessionAcceptsOnlyItsCurrentCapture() {
        let model = TextLookupSessionModel()
        let firstID = UUID()
        let secondID = UUID()

        model.beginLookup(with: capture(id: firstID, term: "first"))
        model.beginLookup(with: capture(id: secondID, term: "second"))

        #expect(!model.accepts(firstID))
        #expect(model.accepts(secondID))
        #expect(model.capture?.term == "second")
    }

    @MainActor
    private func capture(id: UUID, term: String) -> TextLookupCapture {
        TextLookupCapture(
            id: id,
            term: term,
            sentence: nil,
            sourceURL: nil,
            anchorRect: nil,
            sourceApplicationBundleIdentifier: nil
        )
    }
}

import CoreGraphics
import FlashDictIntegrationContracts
import FlashDictIntegrationKit
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

    @Test @MainActor
    func createsFlashcardFromFrozenSelectionWithOriginalContext() async throws {
        let flashDict = FlashDictServiceSpy()
        let model = TextLookupSessionModel(flashDict: flashDict)
        let sourceURL = try #require(URL(string: "https://example.com/article"))
        let capture = TextLookupCapture(
            id: UUID(),
            term: "swift",
            sentence: "Swift keeps the original sentence.",
            sourceURL: sourceURL,
            anchorRect: nil,
            sourceApplicationBundleIdentifier: nil
        )
        model.beginLookup(with: capture)

        let seed = FlashcardSeed(
            dictionaryStableID: "primary",
            dictionaryName: "Main",
            term: "swift",
            headerHTML: nil,
            subHeaderHTML: nil,
            phraseHeaderHTML: nil,
            senseHTML: "<p>moving quickly</p>",
            senseIndex: 0,
            subsenseSelector: nil,
            resourceTagsVersion: 1,
            cssTagsHTML: nil,
            scriptTagsHTML: nil
        )
        model.handle(.senseSelected(SenseSelection(selectionID: "sense-1", cardSeed: seed)))

        let context = try await waitForCreatedContext(in: flashDict)
        #expect(context.sentence == capture.sentence)
        #expect(context.sourceURL == sourceURL)
        #expect(context.userNote == nil)
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

    private func waitForCreatedContext(
        in flashDict: FlashDictServiceSpy
    ) async throws -> FlashcardCreationContext {
        for _ in 0..<20 {
            if let context = await flashDict.createdContext { return context }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Expected a FlashDict create-card request")
        throw CancellationError()
    }
}

private actor FlashDictServiceSpy: TextLookupFlashDictServicing {
    private(set) var createdContext: FlashcardCreationContext?

    func lookup(term: String, requestID: UUID) async throws -> LookupDocument {
        LookupDocument(
            requestID: requestID,
            dictionaryStableID: "primary",
            dictionaryName: "Main",
            term: term,
            htmlDocument: "<html></html>"
        )
    }

    func loadResource(dictionaryStableID: String, key: String) async throws -> LookupResource {
        LookupResource(data: Data(), mimeType: "application/octet-stream")
    }

    func createFlashcard(
        deliveryID: UUID,
        seed: FlashcardSeed,
        context: FlashcardCreationContext
    ) async throws -> FlashcardCreationResult {
        createdContext = context
        return .added(cardID: UUID())
    }
}

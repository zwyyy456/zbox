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

        model.beginLookup(with: capture(id: firstID, term: "first"), targetLanguageIdentifier: "zh-Hans")
        model.beginLookup(with: capture(id: secondID, term: "second"), targetLanguageIdentifier: "zh-Hans")

        #expect(!model.accepts(firstID))
        #expect(model.accepts(secondID))
        #expect(model.capture?.term == "second")
    }

    @Test @MainActor
    func explicitCaptureClearsThePreviousSession() {
        let model = TextLookupSessionModel()
        model.beginLookup(
            with: capture(id: UUID(), term: "previous"),
            targetLanguageIdentifier: "zh-Hans"
        )

        model.beginCapture()

        #expect(model.isCapturing)
        #expect(model.capture == nil)
        #expect(model.captureError == nil)
        if case .idle = model.dictionaryState {
            // Expected while text is being captured.
        } else {
            Issue.record("Expected dictionary state to reset before capture")
        }
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
            anchorRect: nil
        )
        model.beginLookup(with: capture, targetLanguageIdentifier: "zh-Hans")

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

    @Test @MainActor
    func targetLanguageChangeReplacesOnlyTranslationRequest() throws {
        let model = TextLookupSessionModel()
        let capture = TextLookupCapture(
            id: UUID(),
            term: "swift",
            sentence: "Swift is concise.",
            sourceURL: nil,
            anchorRect: nil
        )
        model.beginLookup(with: capture, targetLanguageIdentifier: "zh-Hans")
        let firstRequest = try #require(model.translationRequest)

        model.requestTranslation(targetLanguageIdentifier: "ja")
        let secondRequest = try #require(model.translationRequest)
        model.completeTranslation(
            TranslationResult(
                requestID: firstRequest.id,
                sourceLanguage: Locale.Language(identifier: "en"),
                targetLanguage: firstRequest.targetLanguage,
                translatedText: "stale"
            )
        )

        #expect(model.activeSessionID == capture.id)
        #expect(secondRequest.id != firstRequest.id)
        if case .loading = model.translationState {
            // Expected: the stale completion was ignored.
        } else {
            Issue.record("Expected translation to remain loading for the new request")
        }
    }

    @Test @MainActor
    func staleDictionaryFailureDoesNotReplaceNewerEntry() async throws {
        let flashDict = OutOfOrderFlashDictService()
        let model = TextLookupSessionModel(flashDict: flashDict)
        model.beginLookup(
            with: capture(id: UUID(), term: "old"),
            targetLanguageIdentifier: "zh-Hans"
        )
        await flashDict.waitUntilOldLookupStarts()

        model.handle(.entryRequested(term: "new", anchor: nil))
        await waitUntilLoaded(term: "new", in: model)
        await flashDict.releaseOldLookup()
        await flashDict.waitUntilOldLookupReturns()
        for _ in 0..<20 { await Task.yield() }

        guard case .loaded(let document) = model.dictionaryState else {
            Issue.record("Expected the newer dictionary entry to remain loaded")
            return
        }
        #expect(document.term == "new")
    }

    @Test @MainActor
    func retryUsesTheCurrentDictionaryEntry() async {
        let flashDict = FlashDictServiceSpy(failOnceFor: "linked")
        let model = TextLookupSessionModel(flashDict: flashDict)
        model.beginLookup(
            with: capture(id: UUID(), term: "original"),
            targetLanguageIdentifier: "zh-Hans"
        )
        await waitUntilLoaded(term: "original", in: model)

        model.handle(.entryRequested(term: "linked", anchor: nil))
        await waitUntilDictionaryFails(in: model)
        model.retryDictionaryLookup()
        await waitUntilLoaded(term: "linked", in: model)

        #expect(await flashDict.lookupTerms == ["original", "linked", "linked"])
    }

    @MainActor
    private func waitUntilLoaded(term: String, in model: TextLookupSessionModel) async {
        for _ in 0..<100 {
            if case .loaded(let document) = model.dictionaryState, document.term == term { return }
            await Task.yield()
        }
        Issue.record("Expected dictionary entry \(term) to load")
    }

    @MainActor
    private func waitUntilDictionaryFails(in model: TextLookupSessionModel) async {
        for _ in 0..<100 {
            if case .failed = model.dictionaryState { return }
            await Task.yield()
        }
        Issue.record("Expected dictionary lookup to fail")
    }

    @MainActor
    private func capture(id: UUID, term: String) -> TextLookupCapture {
        TextLookupCapture(
            id: id,
            term: term,
            sentence: nil,
            sourceURL: nil,
            anchorRect: nil
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

private actor OutOfOrderFlashDictService: TextLookupFlashDictServicing {
    private struct ExpectedFailure: Error {}
    private var oldLookupStarted = false
    private var oldLookupReturned = false
    private var oldLookupReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var returnWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func lookup(term: String, requestID: UUID) async throws -> LookupDocument {
        if term == "old" {
            oldLookupStarted = true
            startWaiters.forEach { $0.resume() }
            startWaiters = []
            if !oldLookupReleased {
                await withCheckedContinuation { releaseWaiter = $0 }
            }
            oldLookupReturned = true
            returnWaiters.forEach { $0.resume() }
            returnWaiters = []
            throw ExpectedFailure()
        }
        return LookupDocument(
            requestID: requestID,
            dictionaryStableID: "primary",
            dictionaryName: "Main",
            term: term,
            htmlDocument: "<html></html>"
        )
    }

    func waitUntilOldLookupStarts() async {
        guard !oldLookupStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseOldLookup() {
        oldLookupReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func waitUntilOldLookupReturns() async {
        guard !oldLookupReturned else { return }
        await withCheckedContinuation { returnWaiters.append($0) }
    }

    func loadResource(dictionaryStableID: String, key: String) async throws -> LookupResource {
        LookupResource(data: Data(), mimeType: "application/octet-stream")
    }

    func createFlashcard(
        deliveryID: UUID,
        seed: FlashcardSeed,
        context: FlashcardCreationContext
    ) async throws -> FlashcardCreationResult {
        .added(cardID: UUID())
    }
}

private actor FlashDictServiceSpy: TextLookupFlashDictServicing {
    private(set) var createdContext: FlashcardCreationContext?
    private(set) var lookupTerms: [String] = []
    private var termToFailOnce: String?

    init(failOnceFor term: String? = nil) {
        termToFailOnce = term
    }

    func lookup(term: String, requestID: UUID) async throws -> LookupDocument {
        lookupTerms.append(term)
        if termToFailOnce == term {
            termToFailOnce = nil
            throw FlashDictIntegrationError.requestFailed(message: nil)
        }
        return LookupDocument(
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

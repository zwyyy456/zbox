import Foundation
import CoreGraphics
import Observation
import Vision

nonisolated enum ScreenshotTextRecognizer {
    static var languages: [String] { RecognizeTextRequest().supportedRecognitionLanguages.map(\.minimalIdentifier).sorted() }

    @concurrent static func recognize(_ image: CGImage, language: String, correction: Bool) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = language.isEmpty
        request.usesLanguageCorrection = correction
        if !language.isEmpty { request.recognitionLanguages = [Locale.Language(identifier: language)] }
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        // Keep Vision's reading order and line boundaries; do not invent a multi-column layout.
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

@MainActor @Observable
final class ScreenshotOCRSession {
    var language = "" { didSet { invalidate() } }
    var correction = true { didSet { invalidate() } }
    var text = ""
    private(set) var hasResult = false
    private(set) var isRunning = false
    private(set) var error: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func invalidate() {
        task?.cancel()
        task = nil
        text = ""
        hasResult = false
        isRunning = false
        error = nil
    }

    func run(image: CGImage, edit: ScreenshotEdit) {
        invalidate()
        isRunning = true
        let language = language, correction = correction
        task = Task { [weak self] in
            do {
                let finalImage = try await ScreenshotRenderer.flattened(image: image, edit: edit)
                try Task.checkCancellation()
                let text = try await ScreenshotTextRecognizer.recognize(finalImage, language: language, correction: correction)
                guard !Task.isCancelled, let self else { return }
                self.text = text
                hasResult = true
                isRunning = false
                task = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.error = String(localized: "Text recognition failed. Try another language or a clearer image.")
                isRunning = false
                task = nil
            }
        }
    }
}

import AppKit
import ScreenCaptureKit

enum RecordingTargetKind: CaseIterable {
    case display, window, region

    var title: String {
        switch self {
        case .display: String(localized: "Choose Screen")
        case .window: String(localized: "Choose Window")
        case .region: String(localized: "Choose Area")
        }
    }

    var targetName: String {
        switch self {
        case .display: String(localized: "Screen")
        case .window: String(localized: "Window")
        case .region: String(localized: "Screen Area")
        }
    }
}

struct RecordingTarget {
    enum Source {
        case display(CGDirectDisplayID, sourceRect: CGRect?, displayFrame: CGRect, scale: CGFloat)
        case window(SCContentFilter)
    }

    let kind: RecordingTargetKind
    let name: String
    let pixelSize: CGSize
    let source: Source

    func captureFilter(excluding windowID: CGWindowID) async throws -> SCContentFilter {
        switch source {
        case .window(let filter):
            return filter
        case .display(let id, _, let frame, let scale):
            let content = try await ScreenshotCapture.content()
            guard let display = content.displays.first(where: { $0.displayID == id }),
                  display.frame == frame else { throw RecordingError.targetUnavailable }
            guard let control = content.windows.first(where: { $0.windowID == windowID }) else {
                throw RecordingError.controlWindowUnavailable
            }
            let filter = SCContentFilter(display: display, excludingWindows: [control])
            guard CGFloat(filter.pointPixelScale) == scale else { throw RecordingError.targetUnavailable }
            return filter
        }
    }

    var sourceRect: CGRect? {
        if case .display(_, let rect, _, _) = source { return rect }
        return nil
    }
}

final class RecordingTargetSelection {
    private let regionSelection = ScreenshotSelection()
    private var observer: PickerObserver?
    private var task: Task<Void, Never>?
    private var selection: (id: UUID, completion: @MainActor (Result<RecordingTarget?, Error>) -> Void)?

    func choose(_ kind: RecordingTargetKind, excluding windowID: CGWindowID,
                completion: @escaping @MainActor (Result<RecordingTarget?, Error>) -> Void) {
        cancel()
        let id = UUID()
        selection = (id, completion)
        switch kind {
        case .region:
            task = Task { [weak self] in
                do {
                    let content = try await ScreenshotCapture.content()
                    guard let self, selection?.id == id else { return }
                    regionSelection.show(mode: .area, windows: []) { [weak self] screen, area, _ in
                        guard let self, selection?.id == id else { return }
                        do {
                            let target = try Self.region(on: screen, area: area, content: content)
                            complete(.success(target), id: id)
                        } catch {
                            complete(.failure(error), id: id)
                        }
                    } cancelled: { [weak self] in
                        self?.complete(.success(nil), id: id)
                    }
                } catch {
                    guard let self, selection?.id == id else { return }
                    complete(.failure(error), id: id)
                }
            }
        case .display, .window:
            var configuration = SCContentSharingPickerConfiguration()
            configuration.allowedPickerModes = kind == .display ? .singleDisplay : .singleWindow
            configuration.excludedWindowIDs = [Int(windowID)]
            configuration.allowsChangingSelectedContent = false
            let observer = PickerObserver { [weak self] result in
                // Leave the framework's observer callback before mutating the picker.
                guard let self, self.selection?.id == id, self.task == nil else { return }
                self.task = Task { [weak self] in
                    guard let self, self.selection?.id == id else { return }
                    self.removeObserver()
                    do {
                        let filter = try result.get()
                        let target: RecordingTarget?
                        if let filter {
                            target = try await Self.picked(kind, filter: filter)
                        } else {
                            target = nil
                        }
                        self.complete(.success(target), id: id, keepsPickerActive: target != nil && kind == .window)
                    } catch {
                        self.complete(.failure(error), id: id)
                    }
                }
            }
            self.observer = observer
            let picker = SCContentSharingPicker.shared
            picker.defaultConfiguration = configuration
            picker.maximumStreamCount = 1
            picker.add(observer)
            picker.isActive = true
            picker.present(using: kind == .display ? .display : .window)
        }

    }

    private func complete(_ result: Result<RecordingTarget?, Error>, id: UUID, keepsPickerActive: Bool = false) {
        guard let selection, selection.id == id else { return }
        self.selection = nil
        task = nil
        regionSelection.close()
        if !keepsPickerActive { SCContentSharingPicker.shared.isActive = false }
        selection.completion(result)
    }

    func cancel() {
        selection = nil
        task?.cancel()
        task = nil
        removeObserver()
        SCContentSharingPicker.shared.isActive = false
        regionSelection.close()
    }

    private func removeObserver() {
        if let observer { SCContentSharingPicker.shared.remove(observer) }
        observer = nil
    }

    private static func region(on screen: NSScreen, area: CGRect?, content: SCShareableContent) throws -> RecordingTarget {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let area, let display = content.displays.first(where: { $0.displayID == id }) else {
            throw RecordingError.targetUnavailable
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let source = ScreenshotGeometry.pixelAligned(ScreenshotGeometry.sourceRect(area, in: screen.frame), scale: scale)
        return try displayTarget(.region, display: display, sourceRect: source, size: source.size, scale: scale)
    }

    private static func picked(_ kind: RecordingTargetKind, filter: SCContentFilter) async throws -> RecordingTarget {
        let scale = CGFloat(filter.pointPixelScale)
        switch kind {
        case .display:
            guard filter.style == .display else { throw RecordingError.targetUnavailable }
            // Match the selected frame on macOS 15.0, where the picker filter has no display ID.
            let display: SCDisplay
            if #available(macOS 15.2, *), let selected = filter.includedDisplays.first {
                display = selected
            } else {
                let content = try await ScreenshotCapture.content()
                let matches = content.displays.filter { $0.frame == filter.contentRect }
                guard matches.count == 1, let selected = matches.first else { throw RecordingError.targetUnavailable }
                display = selected
            }
            return try displayTarget(kind, display: display, sourceRect: nil, size: filter.contentRect.size, scale: scale)
        case .window:
            guard filter.style == .window else { throw RecordingError.targetUnavailable }
            let name: String?
            if #available(macOS 15.2, *) { name = filter.includedWindows.first?.title } else { name = nil }
            return RecordingTarget(kind: kind, name: name.flatMap { $0.isEmpty ? nil : $0 } ?? kind.targetName,
                                   pixelSize: try pixelSize(filter.contentRect.size, scale: scale), source: .window(filter))
        case .region:
            preconditionFailure("Area selection uses the screenshot overlay.")
        }
    }

    private static func displayTarget(_ kind: RecordingTargetKind, display: SCDisplay, sourceRect: CGRect?,
                                      size: CGSize, scale: CGFloat) throws -> RecordingTarget {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }
        let name = screen.map {
            kind == .region ? String(localized: "Area on \($0.localizedName)") : $0.localizedName
        } ?? kind.targetName
        return RecordingTarget(kind: kind, name: name, pixelSize: try pixelSize(size, scale: scale),
                               source: .display(display.displayID, sourceRect: sourceRect, displayFrame: display.frame, scale: scale))
    }

    private static func pixelSize(_ points: CGSize, scale: CGFloat) throws -> CGSize {
        let size = CGSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else {
            throw RecordingError.targetUnavailable
        }
        return size
    }
}

@MainActor
private final class PickerObserver: NSObject, SCContentSharingPickerObserver {
    let completion: @MainActor @Sendable (Result<SCContentFilter?, Error>) -> Void

    init(completion: @escaping @MainActor @Sendable (Result<SCContentFilter?, Error>) -> Void) {
        self.completion = completion
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard stream == nil else { return }
        // AppKit retains the non-Sendable SDK filter for delivery on the main thread.
        perform(#selector(deliverFilter(_:)), on: .main, with: filter, waitUntilDone: false)
    }

    @objc private func deliverFilter(_ filter: SCContentFilter) {
        completion(.success(filter))
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil else { return }
        Task { @MainActor in completion(.success(nil)) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in completion(.failure(error)) }
    }
}

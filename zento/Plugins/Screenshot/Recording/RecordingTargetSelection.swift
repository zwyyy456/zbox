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
        case window(CGWindowID, scale: CGFloat)
    }

    let kind: RecordingTargetKind
    let name: String
    let pixelSize: CGSize
    let source: Source

    func captureFilter(excluding windowID: CGWindowID) async throws -> SCContentFilter {
        let content = try await ScreenshotCapture.content()
        switch source {
        case .window(let id, _):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw RecordingError.targetUnavailable
            }
            return SCContentFilter(desktopIndependentWindow: window)
        case .display(let id, _, let frame, let scale):
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

    var pointPixelScale: CGFloat {
        switch source {
        case .display(_, _, _, let scale), .window(_, let scale): scale
        }
    }

    var sourceRect: CGRect? {
        if case .display(_, let rect, _, _) = source { return rect }
        return nil
    }
}

final class RecordingTargetSelection {
    private let targetSelection = ScreenshotSelection()
    private var task: Task<Void, Never>?
    private var selection: (id: UUID, completion: @MainActor (Result<RecordingTarget?, Error>) -> Void)?

    func choose(_ kind: RecordingTargetKind, excluding windowID: CGWindowID,
                completion: @escaping @MainActor (Result<RecordingTarget?, Error>) -> Void) {
        cancel()
        let id = UUID()
        selection = (id, completion)
        task = Task { [weak self] in
            do {
                let content = try await ScreenshotCapture.content()
                guard let self, selection?.id == id else { return }
                let mode: ScreenshotMode = switch kind {
                case .display: .screen
                case .window: .window
                case .region: .area
                }
                let windows = kind == .window ? content.windows.filter { $0.windowID != windowID } : []
                targetSelection.show(mode: mode, windows: windows) { [weak self] screen, area, window in
                    guard let self, selection?.id == id else { return }
                    do {
                        let target: RecordingTarget
                        switch kind {
                        case .region:
                            target = try Self.region(on: screen, area: area, content: content)
                        case .display:
                            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                                throw RecordingError.targetUnavailable
                            }
                            let filter = SCContentFilter(display: display, excludingWindows: [])
                            target = try Self.displayTarget(.display, display: display, sourceRect: nil,
                                                            size: filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
                        case .window:
                            guard let window else { throw RecordingError.targetUnavailable }
                            let filter = SCContentFilter(desktopIndependentWindow: window)
                            let name = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? kind.targetName
                            target = RecordingTarget(kind: kind, name: name,
                                                     pixelSize: try Self.pixelSize(filter.contentRect.size, scale: CGFloat(filter.pointPixelScale)),
                                                     source: .window(window.windowID, scale: CGFloat(filter.pointPixelScale)))
                        }
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
    }

    private func complete(_ result: Result<RecordingTarget?, Error>, id: UUID) {
        guard let selection, selection.id == id else { return }
        self.selection = nil
        task = nil
        targetSelection.close()
        selection.completion(result)
    }

    func cancel() {
        selection = nil
        task?.cancel()
        task = nil
        targetSelection.close()
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

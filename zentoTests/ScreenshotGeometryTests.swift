import CoreGraphics
import Testing
@testable import zento

struct ScreenshotGeometryTests {
    @Test func convertsSelectionOnOffsetDisplays() {
        let screen = CGRect(x: -1280, y: 300, width: 1280, height: 800)
        let area = CGRect(x: -1200, y: 450, width: 400, height: 200)
        #expect(ScreenshotGeometry.sourceRect(area, in: screen) == CGRect(x: 80, y: 450, width: 400, height: 200))
        let global = ScreenshotGeometry.screenRect(area, primaryHeight: 900)
        #expect(global == CGRect(x: -1200, y: 250, width: 400, height: 200))
        #expect(ScreenshotGeometry.screenRect(global, primaryHeight: 900) == area)
        let outside = CGRect(x: -1400, y: 1000, width: 400, height: 400)
        #expect(ScreenshotGeometry.sourceRect(outside, in: screen) == CGRect(x: 0, y: 0, width: 280, height: 100))
    }
    @MainActor @Test func snapshotCropUsesFrozenPixelsAndDisplayCoordinates() throws {
        let size = CGSize(width: 800, height: 600)
        let context = try #require(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let image = try #require(context.makeImage())
        let frame = CGRect(x: -400, y: 100, width: 400, height: 300)
        let area = CGRect(x: -350.5, y: 300, width: 100.5, height: 50.5)
        let rect = ScreenshotGeometry.snapshotPixelRect(area, in: frame, pixels: size)
        #expect(rect == CGRect(x: 99, y: 99, width: 201, height: 101))
        let cropped = try ScreenshotCapture.crop(image, area: area, screenFrame: frame)
        #expect(cropped.width == 201 && cropped.height == 101)
        #expect(ScreenshotGeometry.snapshotPixelRect(CGRect(x: -450, y: 350, width: 100, height: 100),
            in: frame, pixels: size) == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func windowHitTestingDropsDismissedPopoverAndUsesCurrentMainWindowFrame() throws {
        func row(_ id: CGWindowID, _ frame: CGRect, visible: Bool = true) -> [String: Any] {
            [kCGWindowNumber as String: id, kCGWindowBounds as String: frame.dictionaryRepresentation,
             kCGWindowAlpha as String: 1.0, kCGWindowSharingState as String: 1,
             kCGWindowIsOnscreen as String: visible]
        }
        let popup = row(2, CGRect(x: 500, y: 80, width: 250, height: 208))
        let main = row(1, CGRect(x: 0, y: 33, width: 1512, height: 949))
        let point = CGPoint(x: 600, y: 150)
        let before = ScreenshotGeometry.selectableWindowFrames([popup, main])
        #expect(before.first(where: { $0.1.contains(point) })?.0 == 2)
        let after = ScreenshotGeometry.selectableWindowFrames([
            row(2, CGRect(x: 500, y: 80, width: 250, height: 208), visible: false), main
        ])
        #expect(after.first(where: { $0.1.contains(point) })?.0 == 1)
        let moved = ScreenshotGeometry.selectableWindowFrames([row(1, CGRect(x: 800, y: 33, width: 1512, height: 949))])
        #expect(moved.first(where: { $0.1.contains(point) }) == nil)
        #expect(ScreenshotGeometry.selectableWindowFrames([]).isEmpty)
    }

    @Test func frozenWindowGroupsPreserveOverflowAndKeepOtherWindowsIndependent() throws {
        typealias Surface = ScreenshotWindowTargets.Surface
        let surfaces = [
            Surface(id: 9, ownerPID: 20, layer: 0, frame: CGRect(x: 140, y: 120, width: 100, height: 100)),
            Surface(id: 3, ownerPID: 10, layer: 101, frame: CGRect(x: 650, y: 200, width: 100, height: 240)),
            Surface(id: 2, ownerPID: 10, layer: 101, frame: CGRect(x: 450, y: 150, width: 230, height: 240)),
            Surface(id: 4, ownerPID: 10, layer: 0, frame: CGRect(x: 300, y: 120, width: 60, height: 100)),
            Surface(id: 1, ownerPID: 10, layer: 0, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        ]
        let targets = ScreenshotWindowTargets.grouped(surfaces)
        let combined = CGRect(x: 100, y: 100, width: 650, height: 340)
        #expect(targets[1].windowID == 1 && targets[1].captureFrame == combined)
        #expect(targets[2].windowID == 1 && targets[4].captureFrame == combined)
        #expect(targets[0].windowID == 9 && targets[0].captureFrame == surfaces[0].frame)
        #expect(targets[3].windowID == 4 && targets[3].captureFrame == surfaces[3].frame)
        #expect(targets.first(where: { $0.hitFrame.contains(CGPoint(x: 600, y: 200)) })?.windowID == 1)
        #expect(targets.first(where: { $0.hitFrame.contains(CGPoint(x: 160, y: 150)) })?.windowID == 9)
        // Targets are values: later dismissal or movement must not alter a frozen selection.
        let liveAfterDismissal = ScreenshotWindowTargets.grouped([surfaces[4]])
        #expect(liveAfterDismissal[0].captureFrame == surfaces[4].frame)
        #expect(targets[2].captureFrame == combined)
    }

    @MainActor @Test func frozenWindowCropRetainsPopoverPixelsOutsideMainWindow() throws {
        let context = try #require(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        // Draw a popup extending right of the main window, in the same top-left coordinates as Window Server.
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 450, y: 210, width: 230, height: 240))
        let frozen = try #require(context.makeImage())
        let combined = CGRect(x: 100, y: 100, width: 580, height: 300)
        let cocoa = ScreenshotGeometry.screenRect(combined, primaryHeight: 600)
        let crop = try ScreenshotCapture.crop(frozen, area: cocoa, screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(crop.width == 580 && crop.height == 300)
        // CGImage crops may share the original provider. Check the rendered result, not that backing buffer.
        let rendered = try #require(CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        rendered.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let pixel = try #require(rendered.data).assumingMemoryBound(to: UInt8.self)
        let offset = 100 * rendered.bytesPerRow + 550 * 4
        #expect(pixel[offset] == 255)
        #expect(pixel[offset + 1] == 0 && pixel[offset + 2] == 0)
    }

    @Test func windowCandidatesExcludeInvisibleAndNonshareableSurfacesWithoutSizeThreshold() {
        let small = CGRect(x: 50, y: 50, width: 12, height: 12)
        #expect(ScreenshotGeometry.isSelectableWindow(frame: small, alpha: 1, sharingState: 1))
        #expect(!ScreenshotGeometry.isSelectableWindow(frame: small, alpha: 0, sharingState: 1))
        #expect(!ScreenshotGeometry.isSelectableWindow(frame: small, alpha: 1, sharingState: 0))
        #expect(!ScreenshotGeometry.isSelectableWindow(frame: .zero, alpha: 1, sharingState: 1))
    }
}

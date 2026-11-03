import CoreGraphics
import Testing
@testable import zento

struct WindowGeometryTests {
    private let visibleFrame = CGRect(x: 0, y: 24, width: 1_440, height: 876)

    @Test
    func calculatesLeftAndRightHalvesFromVisibleFrame() {
        #expect(
            WindowGeometry.targetRect(for: .leftHalf, in: visibleFrame)
                == CGRect(x: 0, y: 24, width: 720, height: 876)
        )
        #expect(
            WindowGeometry.targetRect(for: .rightHalf, in: visibleFrame)
                == CGRect(x: 720, y: 24, width: 720, height: 876)
        )
    }

    @Test
    func maximizesToVisibleFrame() {
        #expect(WindowGeometry.targetRect(for: .maximize, in: visibleFrame) == visibleFrame)
    }

    @Test
    func convertsBetweenAXAndCocoaCoordinates() {
        let cocoaFrame = CGRect(x: -900, y: 100, width: 800, height: 600)
        let axFrame = WindowGeometry.axRect(fromCocoaRect: cocoaFrame, primaryScreenMaxY: 900)

        #expect(axFrame == CGRect(x: -900, y: 200, width: 800, height: 600))
        #expect(
            WindowGeometry.cocoaRect(fromAXRect: axFrame, primaryScreenMaxY: 900)
                == cocoaFrame
        )
    }

    @Test
    func selectsScreenContainingWindowCenter() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_440, height: 900),
            CGRect(x: -1_280, y: 0, width: 1_280, height: 800),
        ]
        let window = CGRect(x: -500, y: 100, width: 700, height: 500)

        #expect(WindowGeometry.screenIndex(containing: window, screenFrames: screens) == 1)
    }

    @Test
    func fallsBackToLargestIntersectionAndRejectsOffscreenWindows() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_000, height: 800),
            CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
        ]
        let overlappingWindow = CGRect(x: 800, y: 700, width: 500, height: 400)
        let offscreenWindow = CGRect(x: 3_000, y: 100, width: 500, height: 500)

        #expect(WindowGeometry.screenIndex(containing: overlappingWindow, screenFrames: screens) == 1)
        #expect(WindowGeometry.screenIndex(containing: offscreenWindow, screenFrames: screens) == nil)
    }

    @Test func laysOutHalvesQuartersAndThirdsOnOffsetDisplay() throws {
        let screen = CGRect(x: -1200, y: 100, width: 1000, height: 800)
        let expected: [(WindowAction, CGRect)] = [
            (.topHalf, CGRect(x: -1200, y: 500, width: 1000, height: 400)),
            (.bottomHalf, CGRect(x: -1200, y: 100, width: 1000, height: 400)),
            (.topLeftQuarter, CGRect(x: -1200, y: 500, width: 500, height: 400)),
            (.topRightQuarter, CGRect(x: -700, y: 500, width: 500, height: 400)),
            (.bottomLeftQuarter, CGRect(x: -1200, y: 100, width: 500, height: 400)),
            (.bottomRightQuarter, CGRect(x: -700, y: 100, width: 500, height: 400)),
            (.leftThird, CGRect(x: -1200, y: 100, width: 333, height: 800)),
            (.centerThird, CGRect(x: -867, y: 100, width: 334, height: 800)),
            (.rightThird, CGRect(x: -533, y: 100, width: 333, height: 800)),
            (.leftTwoThirds, CGRect(x: -1200, y: 100, width: 667, height: 800)),
            (.rightTwoThirds, CGRect(x: -867, y: 100, width: 667, height: 800)),
        ]
        for (action, frame) in expected {
            #expect(WindowGeometry.targetRect(for: action, in: screen) == frame)
        }
        let thirds = try [WindowAction.leftThird, .centerThird, .rightThird].map {
            try #require(WindowGeometry.targetRect(for: $0, in: screen))
        }
        #expect(thirds[0].maxX == thirds[1].minX)
        #expect(thirds[1].maxX == thirds[2].minX)
        #expect(thirds[2].maxX == screen.maxX)
    }

    @Test func centersWithoutResizingAndFitsRestoreAfterWorkAreaChanges() {
        let window = CGRect(x: 50, y: 50, width: 400, height: 300)
        #expect(WindowGeometry.targetRect(for: .center, in: visibleFrame, currentFrame: window)
            == CGRect(x: 520, y: 312, width: 400, height: 300))
        #expect(WindowGeometry.fitting(window, in: visibleFrame) == window)
        #expect(WindowGeometry.fitting(CGRect(x: -20, y: -20, width: 2000, height: 1500), in: visibleFrame) == visibleFrame)
    }

    @Test func transfersToSmallerAndVerticallyOffsetDisplays() {
        let source = CGRect(x: 0, y: 24, width: 1440, height: 876)
        let target = CGRect(x: -1000, y: 1000, width: 1000, height: 700)
        let window = CGRect(x: 1040, y: 600, width: 400, height: 300)
        let moved = WindowGeometry.moving(window, from: source, to: target)
        #expect(moved == CGRect(x: -400, y: 1400, width: 400, height: 300))
        #expect(WindowGeometry.moving(moved, from: target, to: source) == window)
        #expect(WindowGeometry.moving(source, from: source, to: target) == target)
    }
}

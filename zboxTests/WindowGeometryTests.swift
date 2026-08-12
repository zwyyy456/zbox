import CoreGraphics
import Testing
@testable import zbox

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
}

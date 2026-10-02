import CoreGraphics
import Testing
@testable import zbox

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
}

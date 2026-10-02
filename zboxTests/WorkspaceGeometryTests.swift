import CoreGraphics
import Testing
@testable import zbox

struct WorkspaceGeometryTests {
    @Test func preservesProportionsAcrossDisplaysAndKeepsFrameVisible() {
        let original = CGRect(x: -1600, y: 24, width: 1600, height: 976)
        let frame = CGRect(x: -1600, y: 24, width: 800, height: 976)
        let normalized = WorkspaceGeometry.normalized(frame, in: original)
        let target = CGRect(x: 0, y: 48, width: 1200, height: 752)
        #expect(WorkspaceGeometry.restored(normalized, in: target) == CGRect(x: 0, y: 48, width: 600, height: 752))
        let offscreen = CGRect(x: -0.2, y: 0.6, width: 1.5, height: 0.8)
        let restored = WorkspaceGeometry.restored(offscreen, in: target)
        #expect(target.contains(restored))
        #expect(restored.width == target.width)
        #expect(restored.maxY == target.maxY)
    }
}

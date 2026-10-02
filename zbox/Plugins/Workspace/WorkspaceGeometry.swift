import CoreGraphics

nonisolated enum WorkspaceGeometry {
    static func normalized(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: (frame.minX - visibleFrame.minX) / visibleFrame.width,
               y: (frame.minY - visibleFrame.minY) / visibleFrame.height,
               width: frame.width / visibleFrame.width, height: frame.height / visibleFrame.height)
    }

    static func restored(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width * visibleFrame.width, visibleFrame.width)
        let height = min(frame.height * visibleFrame.height, visibleFrame.height)
        return CGRect(x: min(max(visibleFrame.minX + frame.minX * visibleFrame.width, visibleFrame.minX), visibleFrame.maxX - width),
                      y: min(max(visibleFrame.minY + frame.minY * visibleFrame.height, visibleFrame.minY), visibleFrame.maxY - height),
                      width: width, height: height)
    }
}

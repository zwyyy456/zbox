import AppKit

nonisolated enum WindowGeometry {
    static func cocoaRect(fromAXRect rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func axRect(fromCocoaRect rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func screenIndex(containing windowFrame: CGRect, screenFrames: [CGRect]) -> Int? {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        if let containingIndex = screenFrames.firstIndex(where: { $0.contains(center) }) {
            return containingIndex
        }

        let intersections = screenFrames.enumerated().map { index, screenFrame in
            (index: index, area: area(of: screenFrame.intersection(windowFrame)))
        }
        guard let best = intersections.max(by: { $0.area < $1.area }), best.area > 0 else {
            return nil
        }
        return best.index
    }

    static func targetRect(for action: WindowAction, in visibleFrame: CGRect,
                           currentFrame: CGRect = .zero) -> CGRect? {
        let unit: CGRect
        switch action {
        case .leftHalf: unit = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: unit = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: unit = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .bottomHalf: unit = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .topLeftQuarter: unit = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRightQuarter: unit = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeftQuarter: unit = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRightQuarter: unit = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .leftThird: unit = CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
        case .centerThird: unit = CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .rightThird: unit = CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        case .leftTwoThirds: unit = CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
        case .rightTwoThirds: unit = CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
        case .maximize: return visibleFrame
        case .center:
            return CGRect(x: visibleFrame.midX - currentFrame.width / 2,
                          y: visibleFrame.midY - currentFrame.height / 2,
                          width: currentFrame.width, height: currentFrame.height)
        case .restore, .previousDisplay, .nextDisplay: return nil
        }
        // Round shared boundaries, not widths, so thirds tile without cumulative gaps.
        let x = (visibleFrame.minX + unit.minX * visibleFrame.width).rounded()
        let y = (visibleFrame.minY + unit.minY * visibleFrame.height).rounded()
        return CGRect(x: x, y: y,
                      width: (visibleFrame.minX + unit.maxX * visibleFrame.width).rounded() - x,
                      height: (visibleFrame.minY + unit.maxY * visibleFrame.height).rounded() - y)
    }

    static func fitting(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let width = min(frame.width, visible.width), height = min(frame.height, visible.height)
        return CGRect(x: min(max(frame.minX, visible.minX), visible.maxX - width),
                      y: min(max(frame.minY, visible.minY), visible.maxY - height), width: width, height: height)
    }

    static func moving(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let width = min(frame.width, target.width), height = min(frame.height, target.height)
        let x = source.width > frame.width ? (frame.minX - source.minX) / (source.width - frame.width) : 0.5
        let y = source.height > frame.height ? (frame.minY - source.minY) / (source.height - frame.height) : 0.5
        return fitting(CGRect(x: target.minX + x * (target.width - width),
                              y: target.minY + y * (target.height - height), width: width, height: height), in: target)
    }

    private static func area(of rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isInfinite else { return 0 }
        return rect.width * rect.height
    }
}

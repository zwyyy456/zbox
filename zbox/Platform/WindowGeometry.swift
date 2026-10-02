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

    static func targetRect(for action: WindowAction, in visibleFrame: CGRect) -> CGRect {
        switch action {
        case .leftHalf:
            CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .rightHalf:
            CGRect(
                x: visibleFrame.midX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .maximize:
            visibleFrame
        }
    }

    private static func area(of rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isInfinite else { return 0 }
        return rect.width * rect.height
    }
}

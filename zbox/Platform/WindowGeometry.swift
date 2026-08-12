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

    @MainActor
    static func screen(containing windowFrame: CGRect, screens: [NSScreen]) -> NSScreen? {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        if let containing = screens.first(where: { $0.frame.contains(center) }) {
            return containing
        }

        return screens.max { lhs, rhs in
            lhs.frame.intersection(windowFrame).area < rhs.frame.intersection(windowFrame).area
        }
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
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return width * height
    }
}

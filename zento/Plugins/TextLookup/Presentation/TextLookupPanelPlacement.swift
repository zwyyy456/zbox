import CoreGraphics

nonisolated enum TextLookupPanelPlacement {
    static func origin(
        anchor: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        margin: CGFloat = 12
    ) -> CGPoint {
        let centeredX = anchor.midX - panelSize.width / 2
        let minX = visibleFrame.minX + margin
        let maxX = visibleFrame.maxX - margin - panelSize.width
        let x = min(max(centeredX, minX), max(minX, maxX))

        let belowY = anchor.minY - gap - panelSize.height
        let aboveY = anchor.maxY + gap
        let y = belowY >= visibleFrame.minY + margin
            ? belowY
            : min(aboveY, visibleFrame.maxY - margin - panelSize.height)

        return CGPoint(
            x: x,
            y: max(visibleFrame.minY + margin, y)
        )
    }
}

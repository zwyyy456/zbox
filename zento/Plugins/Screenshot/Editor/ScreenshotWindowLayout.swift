import CoreGraphics

nonisolated enum ScreenshotWindowLayout {
    static func fit(pixels: CGSize, screenScale: CGFloat, visibleSize: CGSize,
                    chromeHeight: CGFloat, contentInsets: CGSize,
                    minimumContentWidth: CGFloat = 480) -> (zoom: CGFloat, frameSize: CGSize) {
        let available = CGSize(width: visibleSize.width * 0.85, height: visibleSize.height * 0.85)
        let zoom = min(1 / screenScale,
                       (available.width - contentInsets.width) / pixels.width,
                       (available.height - chromeHeight - contentInsets.height) / pixels.height)
        return (zoom, CGSize(width: max(minimumContentWidth, pixels.width * zoom + contentInsets.width),
                             height: max(180, pixels.height * zoom + contentInsets.height) + chromeHeight))
    }
}

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ScreenshotFormat: String, CaseIterable, Identifiable {
    case png, jpeg
    var id: String { rawValue }
    var type: UTType { self == .png ? .png : .jpeg }
    var title: String { rawValue.uppercased() }
}

nonisolated enum ScreenshotRenderer {
    static func draw(image: CGImage, edit: ScreenshotEdit, in context: CGContext) {
        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: edit.crop.size))
        context.translateBy(x: -edit.crop.minX, y: -edit.crop.minY)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setLineWidth(3)
        context.setLineCap(.round)
        let red = CGColor(red: 0.95, green: 0.15, blue: 0.12, alpha: 1)
        for mark in edit.marks {
            context.setStrokeColor(red)
            context.setFillColor(red)
            switch mark.tool {
            case .crop: break
            case .rectangle: context.stroke(mark.rect)
            case .redact:
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(mark.rect.integral)
            case .arrow:
                context.move(to: mark.start)
                context.addLine(to: mark.end)
                context.strokePath()
                let angle = atan2(mark.end.y - mark.start.y, mark.end.x - mark.start.x)
                let length = min(18, hypot(mark.end.x - mark.start.x, mark.end.y - mark.start.y) / 2)
                context.move(to: mark.end)
                context.addLine(to: CGPoint(x: mark.end.x - length * cos(angle - .pi / 6),
                                           y: mark.end.y - length * sin(angle - .pi / 6)))
                context.addLine(to: CGPoint(x: mark.end.x - length * cos(angle + .pi / 6),
                                           y: mark.end.y - length * sin(angle + .pi / 6)))
                context.closePath()
                context.fillPath()
            case .text:
                let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
                let attributed = NSAttributedString(string: mark.text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): red,
                ])
                context.textMatrix = .identity
                context.textPosition = mark.start
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
        }
        context.restoreGState()
    }

    @concurrent
    static func flattened(image: CGImage, edit: ScreenshotEdit, whiteBackground: Bool = false) async throws -> CGImage {
        try Task.checkCancellation()
        guard let context = CGContext(data: nil, width: Int(edit.crop.width), height: Int(edit.crop.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScreenshotError.exportFailed }
        if whiteBackground {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: edit.crop.size))
        }
        draw(image: image, edit: edit, in: context)
        try Task.checkCancellation()
        guard let output = context.makeImage() else { throw ScreenshotError.exportFailed }
        return output
    }

    @concurrent
    static func export(image: CGImage, edit: ScreenshotEdit, format: ScreenshotFormat) async throws -> Data {
        let output = try await flattened(image: image, edit: edit, whiteBackground: format == .jpeg)
        return try await encode(output, format: format)
    }

    @concurrent
    static func encode(_ output: CGImage, format: ScreenshotFormat) async throws -> Data {
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
            throw ScreenshotError.exportFailed
        }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ScreenshotError.exportFailed }
        return data as Data
    }
}

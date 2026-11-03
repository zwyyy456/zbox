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
    static func draw(image: CGImage, edit: ScreenshotEdit, in context: CGContext) throws {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: CGRect(origin: .zero, size: edit.crop.size))
        context.translateBy(x: -edit.crop.minX, y: -edit.crop.minY)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Pixelate the captured pixels before vector annotations. Solid covers remain opaque,
        // including where a subsequently added mosaic overlaps them.
        let mosaics = edit.marks.filter { $0.tool == .mosaic }
        if !mosaics.isEmpty {
            let width = max(1, Int(ceil(Double(image.width) / 24)))
            let height = max(1, Int(ceil(Double(image.height) / 24)))
            guard let small = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw ScreenshotError.exportFailed }
            small.interpolationQuality = .high
            small.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let pixels = small.makeImage() else { throw ScreenshotError.exportFailed }
            for mark in mosaics {
                context.saveGState()
                context.clip(to: mark.rect.integral)
                context.interpolationQuality = .none
                context.draw(pixels, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                context.restoreGState()
            }
        }
        context.setLineWidth(3)
        context.setLineCap(.round)
        let red = CGColor(red: 0.95, green: 0.15, blue: 0.12, alpha: 1)
        for mark in edit.marks {
            context.setStrokeColor(red)
            context.setFillColor(red)
            switch mark.tool {
            case .crop, .mosaic: break
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
                let font = CTFontCreateWithName("Helvetica" as CFString, mark.textSize, nil)
                let attributed = NSAttributedString(string: mark.text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): red,
                ])
                context.textMatrix = .identity
                context.textPosition = mark.start
                CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            }
        }
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
        try draw(image: image, edit: edit, in: context)
        try Task.checkCancellation()
        guard let output = context.makeImage() else { throw ScreenshotError.exportFailed }
        return output
    }

    @concurrent
    static func export(image: CGImage, edit: ScreenshotEdit, format: ScreenshotFormat, quality: Double = 0.9) async throws -> Data {
        let output = try await flattened(image: image, edit: edit, whiteBackground: format == .jpeg)
        return try await encode(output, format: format, quality: quality)
    }

    @concurrent
    static func encode(_ output: CGImage, format: ScreenshotFormat, quality: Double = 0.9) async throws -> Data {
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
            throw ScreenshotError.exportFailed
        }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ScreenshotError.exportFailed }
        return data as Data
    }
}

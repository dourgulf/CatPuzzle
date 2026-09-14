import CatPuzzleCore
import CoreGraphics
import UIKit

/// Turns a picked image into the plain pixel buffer `ScreenshotBoardTranscriber`
/// works on. This is the only place in the screenshot-import path that touches
/// an image framework — everything downstream is in the UI-free core.
enum ScreenshotPixelDecoder {
    enum DecodeError: Error, Equatable {
        case unreadableImage
        case drawingFailed
    }

    /// Screenshots top out around 2800px on the long side. The cap only bites
    /// when the picked item is a photo or an export rather than a screenshot,
    /// and it bounds both the redraw and every sampling loop that follows.
    static let maxDimension = 3000

    static func decode(_ data: Data) throws -> ScreenshotPixels {
        guard let image = UIImage(data: data) else {
            throw DecodeError.unreadableImage
        }
        return try decode(image)
    }

    static func decode(_ image: UIImage) throws -> ScreenshotPixels {
        // Redraw rather than reading `cgImage` directly: it normalises
        // orientation, color space, and pixel format in one step, so the
        // transcriber always sees straight sRGB bytes in reading order.
        let size = scaledSize(for: image)
        let bytesPerPixel = 4
        let bytesPerRow = size.width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * size.height)

        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: size.width,
                      height: size.height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return false }
            guard let cgImage = image.cgImage, image.imageOrientation == .up else {
                UIGraphicsPushContext(context)
                defer { UIGraphicsPopContext() }
                image.draw(
                    in: CGRect(x: 0, y: 0, width: size.width, height: size.height)
                )
                return true
            }
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: size.width, height: size.height)
            )
            return true
        }
        guard drew else { throw DecodeError.drawingFailed }

        return try ScreenshotPixels(
            width: size.width,
            height: size.height,
            rgba: buffer
        )
    }

    private static func scaledSize(for image: UIImage) -> (width: Int, height: Int) {
        let pixelWidth = max(1, Int((image.size.width * image.scale).rounded()))
        let pixelHeight = max(1, Int((image.size.height * image.scale).rounded()))
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension else { return (pixelWidth, pixelHeight) }
        let ratio = Double(maxDimension) / Double(longest)
        return (
            max(1, Int((Double(pixelWidth) * ratio).rounded())),
            max(1, Int((Double(pixelHeight) * ratio).rounded()))
        )
    }
}

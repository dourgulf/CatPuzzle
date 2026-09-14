/// A decoded screenshot as plain RGBA bytes.
///
/// The board transcriber below works on pixels, not on images: keeping the
/// decoding step outside this target is what lets the whole detection
/// pipeline stay in the UI-free core (see CLAUDE.md) and be tested from
/// `swift test` against synthetic boards, with no image framework anywhere.
/// The app layer decodes a `UIImage` into this shape and hands it over.
public struct ScreenshotPixels: Equatable, Sendable {
    /// One opaque sample. Alpha is dropped during decoding — screenshots are
    /// opaque, and the detection thresholds are all defined on RGB.
    public struct Color: Equatable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Squared RGB distance. Squared, because every comparison here is
        /// against a fixed threshold and the square root buys nothing.
        func squaredDistance(to other: Color) -> Int {
            let dr = Int(red) - Int(other.red)
            let dg = Int(green) - Int(other.green)
            let db = Int(blue) - Int(other.blue)
            return dr * dr + dg * dg + db * db
        }
    }

    public enum PixelError: Error, Equatable, Sendable {
        case invalidDimensions
        case bufferTooSmall(expected: Int, actual: Int)
    }

    public let width: Int
    public let height: Int

    /// Row-major RGB triples, 3 bytes per pixel.
    private let samples: [UInt8]

    /// - Parameter rgb: row-major, exactly `width * height * 3` bytes.
    public init(width: Int, height: Int, rgb: [UInt8]) throws {
        guard width > 0, height > 0 else {
            throw PixelError.invalidDimensions
        }
        let expected = width * height * 3
        guard rgb.count == expected else {
            throw PixelError.bufferTooSmall(expected: expected, actual: rgb.count)
        }
        self.width = width
        self.height = height
        self.samples = rgb
    }

    /// - Parameter rgba: row-major, 4 bytes per pixel; alpha is discarded.
    public init(width: Int, height: Int, rgba: [UInt8]) throws {
        guard width > 0, height > 0 else {
            throw PixelError.invalidDimensions
        }
        let expected = width * height * 4
        guard rgba.count == expected else {
            throw PixelError.bufferTooSmall(expected: expected, actual: rgba.count)
        }
        var rgb = [UInt8]()
        rgb.reserveCapacity(width * height * 3)
        for pixel in stride(from: 0, to: rgba.count, by: 4) {
            rgb.append(rgba[pixel])
            rgb.append(rgba[pixel + 1])
            rgb.append(rgba[pixel + 2])
        }
        try self.init(width: width, height: height, rgb: rgb)
    }

    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    /// Reads one pixel, clamping to the edge. Clamping (rather than
    /// returning nil) keeps every sampling loop below branch-free; all of
    /// them stay inside the frame anyway, and an off-by-one at a border
    /// should not change a cell's classification.
    public func color(x: Int, y: Int) -> Color {
        let cx = min(max(x, 0), width - 1)
        let cy = min(max(y, 0), height - 1)
        let offset = (cy * width + cx) * 3
        return Color(
            red: samples[offset],
            green: samples[offset + 1],
            blue: samples[offset + 2]
        )
    }
}

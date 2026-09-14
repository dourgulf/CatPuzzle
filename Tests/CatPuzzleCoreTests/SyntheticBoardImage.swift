import XCTest
@testable import CatPuzzleCore

/// Draws a puzzle board the way the two apps whose screenshots this feature
/// reads actually draw one: colored cells on a light card, separated by
/// hairline gaps, with a ✕ or a cat glyph on some of them.
///
/// Real screenshots cannot be checked in (`Docs/demo` is local design input),
/// so the tests build their own boards instead. The geometry and the two cat
/// styles here are modelled on measurements taken from those screenshots, so a
/// synthetic board exercises the same thresholds a real one does.
struct SyntheticBoardImage {
    /// The reference app's dark cat face, and this app's light pawprint disc.
    /// They are opposites in brightness on purpose: the transcriber classifies
    /// by *shape*, so both must read as a cat.
    enum CatGlyph {
        case darkFace
        case lightDisc
    }

    static let backdrop = ScreenshotPixels.Color(red: 255, green: 255, blue: 255)

    /// This app's Region palette, plus two more so a 12×12 board can be drawn.
    static let palette: [ScreenshotPixels.Color] = [
        .init(red: 237, green: 134, blue: 213),
        .init(red: 56, green: 170, blue: 112),
        .init(red: 244, green: 207, blue: 104),
        .init(red: 93, green: 131, blue: 180),
        .init(red: 174, green: 118, blue: 84),
        .init(red: 137, green: 207, blue: 120),
        .init(red: 255, green: 153, blue: 85),
        .init(red: 136, green: 119, blue: 216),
        .init(red: 73, green: 191, blue: 207),
        .init(red: 239, green: 105, blue: 112),
        .init(red: 150, green: 150, blue: 150),
        .init(red: 40, green: 110, blue: 70),
    ]

    var cellSide = 40
    var gap = 6
    var margin = 24
    /// Extra backdrop above the board, standing in for the level header.
    var headerHeight = 60
    var catGlyph: CatGlyph = .darkFace
    /// A full-width colored banner drawn over the header, like the promo strip
    /// the reference app shows after a retry.
    var banner = false

    func render(
        regionIDs: [[Int]],
        states: [[CellState]]? = nil
    ) -> ScreenshotPixels {
        let size = regionIDs.count
        let boardSide = size * cellSide + (size - 1) * gap
        let width = boardSide + margin * 2
        let height = boardSide + margin * 2 + headerHeight

        var canvas = Canvas(width: width, height: height, fill: Self.backdrop)
        if banner {
            canvas.fill(
                x: 0,
                y: 8,
                width: width,
                height: 34,
                with: .init(red: 60, green: 52, blue: 48)
            )
        }

        let originX = margin
        let originY = margin + headerHeight
        for row in 0..<size {
            for column in 0..<size {
                let x = originX + column * (cellSide + gap)
                let y = originY + row * (cellSide + gap)
                let fill = Self.palette[regionIDs[row][column] % Self.palette.count]
                canvas.fill(x: x, y: y, width: cellSide, height: cellSide, with: fill)
                switch states?[row][column] ?? .empty {
                case .empty: break
                case .excluded: drawCross(&canvas, x: x, y: y)
                case .cat: drawCat(&canvas, x: x, y: y)
                }
            }
        }
        return canvas.pixels()
    }

    /// Two diagonal strokes. Their defining property, and the one the
    /// transcriber keys on, is that the cell's own axes stay clear.
    private func drawCross(_ canvas: inout Canvas, x: Int, y: Int) {
        let inset = Int(Double(cellSide) * 0.2)
        let thickness = max(2, Int(Double(cellSide) * 0.1))
        for step in inset...(cellSide - inset) {
            for offset in 0..<thickness {
                canvas.set(x: x + step + offset, y: y + step, to: Self.backdrop)
                canvas.set(
                    x: x + step + offset,
                    y: y + cellSide - step,
                    to: Self.backdrop
                )
            }
        }
    }

    private func drawCat(_ canvas: inout Canvas, x: Int, y: Int) {
        let radius = Double(cellSide) * 0.37
        let center = Double(cellSide) / 2
        let body: ScreenshotPixels.Color = catGlyph == .darkFace
            ? .init(red: 28, green: 26, blue: 30)
            : Self.backdrop
        for dy in 0..<cellSide {
            for dx in 0..<cellSide {
                let ox = Double(dx) + 0.5 - center
                let oy = Double(dy) + 0.5 - center
                guard ox * ox + oy * oy <= radius * radius else { continue }
                canvas.set(x: x + dx, y: y + dy, to: body)
            }
        }
        guard catGlyph == .lightDisc else { return }
        // The pawprint inside the white disc.
        let pawRadius = Double(cellSide) * 0.14
        for dy in 0..<cellSide {
            for dx in 0..<cellSide {
                let ox = Double(dx) + 0.5 - center
                let oy = Double(dy) + 0.5 - center
                guard ox * ox + oy * oy <= pawRadius * pawRadius else { continue }
                canvas.set(
                    x: x + dx,
                    y: y + dy,
                    to: .init(red: 73, green: 53, blue: 63)
                )
            }
        }
    }

    private struct Canvas {
        let width: Int
        let height: Int
        var bytes: [UInt8]

        init(width: Int, height: Int, fill: ScreenshotPixels.Color) {
            self.width = width
            self.height = height
            bytes = [UInt8](repeating: 0, count: width * height * 3)
            self.fill(x: 0, y: 0, width: width, height: height, with: fill)
        }

        mutating func set(x: Int, y: Int, to color: ScreenshotPixels.Color) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let offset = (y * width + x) * 3
            bytes[offset] = color.red
            bytes[offset + 1] = color.green
            bytes[offset + 2] = color.blue
        }

        mutating func fill(
            x: Int,
            y: Int,
            width fillWidth: Int,
            height fillHeight: Int,
            with color: ScreenshotPixels.Color
        ) {
            for row in y..<(y + fillHeight) {
                for column in x..<(x + fillWidth) {
                    set(x: column, y: row, to: color)
                }
            }
        }

        func pixels() -> ScreenshotPixels {
            // Dimensions come from this type, so the throwing initialiser
            // cannot fail here.
            try! ScreenshotPixels(width: width, height: height, rgb: bytes)
        }
    }
}

/// Region IDs relabelled in row-major first-seen order, so a test compares the
/// Region *partition* rather than which integer each Region happened to get.
func canonicalRegionIDs(_ regionIDs: [[Int]]) -> [[Int]] {
    var mapping: [Int: Int] = [:]
    return regionIDs.map { row in
        row.map { original in
            if let assigned = mapping[original] { return assigned }
            let next = mapping.count
            mapping[original] = next
            return next
        }
    }
}

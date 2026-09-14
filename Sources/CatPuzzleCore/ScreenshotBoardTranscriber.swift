/// One board read back out of a screenshot.
public struct TranscribedScreenshotBoard: Equatable, Sendable {
    public let size: Int
    public let regionIDs: [[Int]]
    /// What each cell was drawn as: a placed cat, a ✕ mark, or nothing.
    public let states: [[CellState]]
    /// Representative on-screen color per Region, indexed by Region ID. The
    /// app names Regions to the player by color, so the parsed colors are
    /// worth keeping rather than throwing away with the pixels.
    public let regionColors: [ScreenshotPixels.Color]

    public init(
        size: Int,
        regionIDs: [[Int]],
        states: [[CellState]],
        regionColors: [ScreenshotPixels.Color]
    ) {
        self.size = size
        self.regionIDs = regionIDs
        self.states = states
        self.regionColors = regionColors
    }

    public func state(atRow row: Int, column: Int) -> CellState {
        states[row][column]
    }
}

public enum ScreenshotTranscriptionError: Error, Equatable, Sendable {
    /// No large block of non-backdrop pixels — probably not a puzzle screenshot.
    case boardNotFound
    /// Grid lines were found, but they do not describe a square board.
    case nonSquareGrid(rows: Int, columns: Int)
    case unsupportedBoardSize(Int)
    /// A CatPuzzle board has exactly one Region per row; anything else means
    /// colors were split or merged and the transcription cannot be trusted.
    case regionCountMismatch(regions: Int, size: Int)
}

/// Reads a CatPuzzle board — Region layout plus the marks currently on it —
/// out of a screenshot.
///
/// The thresholds below are not guesses: they were measured against 47 real
/// screenshots (4313 cells) and reproduce every cell's Region and mark. The
/// pipeline is the Swift port of `Scripts/solve_step_by_step.py`'s parser,
/// with two deliberate improvements over it:
///
///  - Region color is read from a band just inside each cell's border rather
///    than from its interior. A cat or ✕ glyph never reaches there, so the
///    color is the flat Region fill even on a marked cell. (The script's
///    interior median split two of the 47 boards into one Region too many.)
///  - A mark is classified by how much of the cell differs from that Region
///    color, and by whether the difference sits on the cell's *axes*. A ✕ has
///    both diagonals covered and its axes clear; any glyph with a body — the
///    reference app's cat face, this app's pawprint disc — covers the axes.
///    That is a property of the shapes, not of one app's palette, so it also
///    reads back a screenshot of CatPuzzle itself, whose ✕ is white and whose
///    cat is a *light* disc rather than a dark one.
public enum ScreenshotBoardTranscriber {
    // Backdrop colors: the page background and the white card / grid-line
    // gaps. Any pixel near either is "not part of a cell".
    private static let backdrops: [ScreenshotPixels.Color] = [
        .init(red: 247, green: 242, blue: 239),
        .init(red: 255, green: 255, blue: 255),
    ]
    private static let backdropTolerance = 10

    /// Fraction of a scanline that must be colorful for it to be board rather
    /// than header text or a small rule-icon thumbnail.
    private static let boardFractionThreshold = 0.6
    /// Below this, a scanline is a grid-line gap between two cells.
    private static let gapFractionThreshold = 0.15

    /// Two cell colors closer than this are the same Region (squared: 40²).
    private static let regionMergeSquaredDistance = 1600
    /// A pixel further than this from the Region color belongs to a mark (60²).
    private static let markSquaredDistance = 3600

    private static let emptyCoverage = 0.08
    private static let catCoverage = 0.62
    private static let catAxisFraction = 0.5

    /// How far from square a candidate board may be. Screenshots are not
    /// pixel-perfect: rounded corners and antialiasing move an edge by a few
    /// pixels either way.
    private static let squareTolerance = 0.12

    private static let supportedSizes = 4...12

    public static func transcribe(
        _ pixels: ScreenshotPixels
    ) throws -> TranscribedScreenshotBoard {
        // Two passes: locate the board inside the whole screenshot, then
        // re-measure within it so the header and footer cannot bias the grid
        // detection or any cell sample.
        let frame = Rect(
            x0: 0,
            y0: 0,
            x1: pixels.width - 1,
            y1: pixels.height - 1
        )
        guard let coarse = boardBounds(in: pixels, within: frame) else {
            throw ScreenshotTranscriptionError.boardNotFound
        }
        // Re-measure inside the board so the header, footer, and any banner
        // that survived the first pass cannot bias the grid detection or a
        // cell sample. The coarse bounds stand if the second pass finds
        // nothing tighter.
        let bounds = boardBounds(in: pixels, within: coarse) ?? coarse

        let xEdges = cellEdges(in: pixels, bounds: bounds, axis: .horizontal)
        let yEdges = cellEdges(in: pixels, bounds: bounds, axis: .vertical)
        let columns = xEdges.count - 1
        let rows = yEdges.count - 1
        guard rows == columns else {
            throw ScreenshotTranscriptionError.nonSquareGrid(
                rows: rows,
                columns: columns
            )
        }
        guard supportedSizes.contains(rows) else {
            throw ScreenshotTranscriptionError.unsupportedBoardSize(rows)
        }

        var regionIDs = [[Int]](
            repeating: [Int](repeating: 0, count: columns),
            count: rows
        )
        var states = [[CellState]](
            repeating: [CellState](repeating: .empty, count: columns),
            count: rows
        )
        var regionColors: [ScreenshotPixels.Color] = []

        for row in 0..<rows {
            for column in 0..<columns {
                let cell = Rect(
                    x0: xEdges[column],
                    y0: yEdges[row],
                    x1: xEdges[column + 1],
                    y1: yEdges[row + 1]
                )
                let fill = regionColor(in: pixels, cell: cell)
                states[row][column] = classify(
                    in: pixels,
                    cell: cell,
                    fill: fill
                )

                if let existing = regionColors.firstIndex(where: {
                    $0.squaredDistance(to: fill) <= regionMergeSquaredDistance
                }) {
                    regionIDs[row][column] = existing
                } else {
                    regionIDs[row][column] = regionColors.count
                    regionColors.append(fill)
                }
            }
        }

        guard regionColors.count == rows else {
            throw ScreenshotTranscriptionError.regionCountMismatch(
                regions: regionColors.count,
                size: rows
            )
        }

        return TranscribedScreenshotBoard(
            size: rows,
            regionIDs: regionIDs,
            states: states,
            regionColors: regionColors
        )
    }

    // MARK: - Locating the board

    struct Rect: Equatable {
        let x0: Int
        let y0: Int
        let x1: Int
        let y1: Int

        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
    }

    private enum Axis {
        case horizontal
        case vertical
    }

    private static func isBackdrop(_ color: ScreenshotPixels.Color) -> Bool {
        backdrops.contains { backdrop in
            abs(Int(color.red) - Int(backdrop.red)) <= backdropTolerance
                && abs(Int(color.green) - Int(backdrop.green)) <= backdropTolerance
                && abs(Int(color.blue) - Int(backdrop.blue)) <= backdropTolerance
        }
    }

    /// The board's pixel bounds: the largest square-ish block of non-backdrop
    /// pixels.
    ///
    /// Squareness is the load-bearing test, not size — a CatPuzzle board
    /// always is one. Taking the largest colorful block instead would swallow
    /// a full-width banner drawn over the screenshot (the reference app shows
    /// one after a retry), which is exactly the case this rejects.
    private static func boardBounds(
        in pixels: ScreenshotPixels,
        within rect: Rect,
        step: Int = 3,
        maxGapPixels: Int = 24
    ) -> Rect? {
        let maxGap = maxGapPixels / step + 1
        let xs = Array(stride(from: rect.x0, through: rect.x1, by: step))
        let ys = Array(stride(from: rect.y0, through: rect.y1, by: step))
        guard !xs.isEmpty, !ys.isEmpty else { return nil }

        let rowIsBoard = ys.map { y in
            let colorful = xs.count { !isBackdrop(pixels.color(x: $0, y: y)) }
            return Double(colorful) / Double(xs.count) > boardFractionThreshold
        }

        var best: Rect?
        for band in runs(rowIsBoard, maxGap: maxGap) {
            let y0 = ys[band.lowerBound]
            let y1 = ys[band.upperBound]
            let bandYs = Array(stride(from: y0, through: y1, by: step))
            let columnIsBoard = xs.map { x in
                let colorful = bandYs.count { !isBackdrop(pixels.color(x: x, y: $0)) }
                return Double(colorful) / Double(max(1, bandYs.count))
                    > boardFractionThreshold
            }
            for span in runs(columnIsBoard, maxGap: maxGap) {
                let candidate = Rect(
                    x0: xs[span.lowerBound],
                    y0: y0,
                    x1: xs[span.upperBound],
                    y1: y1
                )
                let longest = max(candidate.width, candidate.height)
                guard longest > 0,
                      Double(abs(candidate.width - candidate.height))
                        <= squareTolerance * Double(longest) else { continue }
                if candidate.width * candidate.height
                    > (best?.width ?? 0) * (best?.height ?? 0) {
                    best = candidate
                }
            }
        }
        return best
    }

    /// Every maximal run of `true`, tolerating gaps of up to `maxGap` false
    /// entries so the thin grid lines inside the board do not split one — only
    /// the real backdrop margins around the board do.
    static func runs(_ flags: [Bool], maxGap: Int) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for index in 0...flags.count {
            let flag = index < flags.count && flags[index]
            if flag, start == nil {
                start = index
            } else if !flag, let begin = start {
                runs.append(begin...(index - 1))
                start = nil
            }
        }
        guard var merged = runs.first else { return [] }
        var result: [ClosedRange<Int>] = []
        for run in runs.dropFirst() {
            if run.lowerBound - merged.upperBound - 1 <= maxGap {
                merged = merged.lowerBound...run.upperBound
            } else {
                result.append(merged)
                merged = run
            }
        }
        result.append(merged)
        return result
    }

    /// Pixel offsets of the grid-line gaps along one axis, including both
    /// outer edges, so consecutive pairs delimit one row or column of cells.
    private static func cellEdges(
        in pixels: ScreenshotPixels,
        bounds: Rect,
        axis: Axis,
        step: Int = 2
    ) -> [Int] {
        let positions: [Int]
        let cross: [Int]
        switch axis {
        case .horizontal:
            positions = Array(stride(from: bounds.x0, through: bounds.x1, by: step))
            cross = Array(stride(from: bounds.y0, through: bounds.y1, by: step))
        case .vertical:
            positions = Array(stride(from: bounds.y0, through: bounds.y1, by: step))
            cross = Array(stride(from: bounds.x0, through: bounds.x1, by: step))
        }
        guard let first = positions.first, let last = positions.last else { return [] }

        let isGap = positions.map { position in
            let colorful = cross.count { other in
                switch axis {
                case .horizontal: !isBackdrop(pixels.color(x: position, y: other))
                case .vertical: !isBackdrop(pixels.color(x: other, y: position))
                }
            }
            return Double(colorful) / Double(max(1, cross.count)) < gapFractionThreshold
        }

        var edges = [first]
        var index = 0
        while index < positions.count {
            guard isGap[index] else {
                index += 1
                continue
            }
            var end = index
            while end < positions.count, isGap[end] { end += 1 }
            let middle = positions[(index + end - 1) / 2]
            if middle - edges[edges.count - 1] > 5 {
                edges.append(middle)
            }
            index = end
        }
        if edges[edges.count - 1] != last {
            edges.append(last)
        }
        return edges
    }

    // MARK: - Reading one cell

    /// The Region fill under whatever is drawn on the cell, sampled from a
    /// band just inside its border. Near-white samples are dropped so the
    /// cell's own hairline stroke does not wash the median out.
    private static func regionColor(
        in pixels: ScreenshotPixels,
        cell: Rect
    ) -> ScreenshotPixels.Color {
        let inset = max(2, Int(Double(min(cell.width, cell.height)) * 0.10))
        var reds: [UInt8] = []
        var greens: [UInt8] = []
        var blues: [UInt8] = []

        func sample(x: Int, y: Int) {
            let color = pixels.color(x: x, y: y)
            // Rounded corners expose the card behind the cell; the band stays
            // on the middle 56% of each edge, but drop white anyway.
            guard color.red < 231 || color.green < 231 || color.blue < 231 else { return }
            reds.append(color.red)
            greens.append(color.green)
            blues.append(color.blue)
        }

        for offset in Int(Double(cell.width) * 0.22)..<Int(Double(cell.width) * 0.78) {
            sample(x: cell.x0 + offset, y: cell.y0 + inset)
            sample(x: cell.x0 + offset, y: cell.y1 - inset)
        }
        for offset in Int(Double(cell.height) * 0.22)..<Int(Double(cell.height) * 0.78) {
            sample(x: cell.x0 + inset, y: cell.y0 + offset)
            sample(x: cell.x1 - inset, y: cell.y0 + offset)
        }

        guard !reds.isEmpty else {
            return pixels.color(
                x: (cell.x0 + cell.x1) / 2,
                y: (cell.y0 + cell.y1) / 2
            )
        }
        return ScreenshotPixels.Color(
            red: median(&reds),
            green: median(&greens),
            blue: median(&blues)
        )
    }

    private static func median(_ values: inout [UInt8]) -> UInt8 {
        values.sort()
        return values[values.count / 2]
    }

    private static func classify(
        in pixels: ScreenshotPixels,
        cell: Rect,
        fill: ScreenshotPixels.Color
    ) -> CellState {
        func differs(x: Int, y: Int) -> Bool {
            pixels.color(x: x, y: y).squaredDistance(to: fill) > markSquaredDistance
        }

        let insetX = Int(Double(cell.width) * 0.15)
        let insetY = Int(Double(cell.height) * 0.15)
        var marked = 0
        var total = 0
        for y in stride(from: cell.y0 + insetY, to: cell.y1 - insetY, by: 2) {
            for x in stride(from: cell.x0 + insetX, to: cell.x1 - insetX, by: 2) {
                total += 1
                if differs(x: x, y: y) { marked += 1 }
            }
        }
        let coverage = Double(marked) / Double(max(1, total))
        if coverage < emptyCoverage { return .empty }

        // A ✕ leaves both axes clear; a cat glyph's body crosses them.
        let side = Double(min(cell.width, cell.height))
        let centerX = (cell.x0 + cell.x1) / 2
        let centerY = (cell.y0 + cell.y1) / 2
        var onAxis = 0
        var axisProbes = 0
        for scale in [0.24, 0.34] {
            let radius = Int(side * scale)
            for probe in [(radius, 0), (-radius, 0), (0, radius), (0, -radius)] {
                axisProbes += 1
                if differs(x: centerX + probe.0, y: centerY + probe.1) { onAxis += 1 }
            }
        }
        let axisFraction = Double(onAxis) / Double(axisProbes)

        return coverage >= catCoverage || axisFraction >= catAxisFraction
            ? .cat
            : .excluded
    }
}

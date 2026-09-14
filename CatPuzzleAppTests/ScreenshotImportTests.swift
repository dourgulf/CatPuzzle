import XCTest
@testable import CatPuzzle
import CatPuzzleCore
import UIKit

/// Covers the app half of screenshot import: turning a picked image into
/// pixels, and turning an import failure into something a player can act on.
/// The detection itself is covered in `CatPuzzleCoreTests`.
final class ScreenshotImportTests: XCTestCase {
    private let regionIDs = BuiltInLevels.meadow.regionIDs

    // MARK: - Decoding

    func testDecodingAScreenshotKeepsItsPixelDimensions() throws {
        let image = renderBoardImage(scale: 1)

        let pixels = try ScreenshotPixelDecoder.decode(image)

        XCTAssertEqual(pixels.width, Int(image.size.width))
        XCTAssertEqual(pixels.height, Int(image.size.height))
    }

    /// A screenshot's `size` is in points; its pixels are `scale` times that.
    /// Decoding has to work in pixels or every cell measurement is off.
    func testDecodingUsesPixelsRatherThanPoints() throws {
        let image = renderBoardImage(scale: 3)

        let pixels = try ScreenshotPixelDecoder.decode(image)

        XCTAssertEqual(pixels.width, Int(image.size.width) * 3)
        XCTAssertEqual(pixels.height, Int(image.size.height) * 3)
    }

    func testAnOversizedImageIsScaledDownToTheCap() throws {
        let image = renderBoardImage(pointSide: 4000, scale: 1)

        let pixels = try ScreenshotPixelDecoder.decode(image)

        XCTAssertEqual(
            max(pixels.width, pixels.height),
            ScreenshotPixelDecoder.maxDimension
        )
    }

    func testDataThatIsNotAnImageIsRejected() {
        XCTAssertThrowsError(
            try ScreenshotPixelDecoder.decode(Data("not an image".utf8))
        ) {
            XCTAssertEqual(
                $0 as? ScreenshotPixelDecoder.DecodeError,
                .unreadableImage
            )
        }
    }

    // MARK: - End to end

    @MainActor
    func testARenderedBoardImportsIntoAPlayableGame() throws {
        let pixels = try ScreenshotPixelDecoder.decode(renderBoardImage(scale: 2))

        let imported = try ScreenshotLevelImporter.makeLevel(from: pixels)
        let viewModel = ScreenshotGameFactory.makeViewModel(
            imported: imported,
            mode: .exploration
        )

        XCTAssertEqual(viewModel.puzzle, imported.puzzle)
        XCTAssertEqual(viewModel.level.size, 6)
        XCTAssertFalse(viewModel.isSolved)
    }

    // MARK: - Copy

    /// Every failure has to say something different and actionable — a player
    /// who picked the wrong photo and a player whose board was covered by a
    /// banner need different advice.
    func testEveryImportFailureGetsItsOwnAdvice() {
        let messages = [
            ScreenshotImportCopy.message(for: ScreenshotImportError.transcription(.boardNotFound)),
            ScreenshotImportCopy.message(for: ScreenshotImportError.transcription(.nonSquareGrid(rows: 8, columns: 3))),
            ScreenshotImportCopy.message(for: ScreenshotImportError.transcription(.unsupportedBoardSize(14))),
            ScreenshotImportCopy.message(for: ScreenshotImportError.transcription(.regionCountMismatch(regions: 9, size: 10))),
            ScreenshotImportCopy.message(for: ScreenshotImportError.invalidLevel(.invalidRegionCount)),
            ScreenshotImportCopy.message(for: ScreenshotImportError.noSolution),
            ScreenshotImportCopy.message(for: ScreenshotImportError.multipleSolutions),
            ScreenshotImportCopy.message(for: ScreenshotImportError.searchInconclusive),
        ]

        XCTAssertEqual(Set(messages).count, messages.count)
        XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(
            ScreenshotImportCopy
                .message(for: ScreenshotImportError.transcription(.unsupportedBoardSize(14)))
                .contains("14 × 14")
        )
        XCTAssertEqual(
            ScreenshotImportCopy.message(for: ScreenshotPixelDecoder.DecodeError.unreadableImage),
            ScreenshotImportCopy.unreadable
        )
    }

    // MARK: - Helpers

    /// Draws a board the way the game does: colored cells on a white card,
    /// separated by hairline gaps, with a header band above it.
    private func renderBoardImage(
        pointSide: CGFloat = 300,
        scale: CGFloat
    ) -> UIImage {
        let size = regionIDs.count
        let gap = pointSide / 60
        let cell = (pointSide - gap * CGFloat(size - 1)) / CGFloat(size)
        let header = pointSide / 5
        let margin = pointSide / 12
        let canvas = CGSize(
            width: pointSide + margin * 2,
            height: pointSide + margin * 2 + header
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            for row in 0..<size {
                for column in 0..<size {
                    UIColor(CatPuzzleTheme.regionColor(for: regionIDs[row][column]))
                        .setFill()
                    context.fill(CGRect(
                        x: margin + CGFloat(column) * (cell + gap),
                        y: margin + header + CGFloat(row) * (cell + gap),
                        width: cell,
                        height: cell
                    ))
                }
            }
        }
    }
}

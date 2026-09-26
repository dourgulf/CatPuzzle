import SwiftUI
import XCTest
@testable import CatPuzzle

@MainActor
final class GameStatusBarRenderTests: XCTestCase {
    func testSixRegionStatusRendersOffscreen() throws {
        try attachRendering(
            regionCount: 6,
            completedRegions: [0, 2],
            remainingLives: 2,
            name: "six-region-status"
        )
    }

    func testTenRegionStatusRendersOffscreen() throws {
        try attachRendering(
            regionCount: 10,
            completedRegions: [0, 2, 5],
            remainingLives: 1,
            name: "ten-region-status"
        )
    }

    func testCompactRuleInfoStripRendersOffscreen() throws {
        try attachRuleInfoStrip(locale: "en", name: "compact-rule-strip-en")
    }

    func testCompactChineseRuleInfoStripRendersOffscreen() throws {
        try attachRuleInfoStrip(locale: "zh-Hans", name: "compact-rule-strip-zh-Hans")
    }

    private func attachRuleInfoStrip(locale: String, name: String) throws {
        let content = RuleInfoStrip()
            .padding(.horizontal, 16)
            .frame(width: 393, height: 72)
            .background(CatPuzzleTheme.background)
            .environment(\.locale, Locale(identifier: locale))
        try attach(content, name: name)
    }

    private func attachRendering(
        regionCount: Int,
        completedRegions: Set<Int>,
        remainingLives: Int,
        name: String
    ) throws {
        let content = GameStatusBar(
            regionIDs: Array(0..<regionCount),
            occupiedRegionIDs: completedRegions,
            remainingLives: remainingLives,
            maxLives: 3
        )
        .padding(.horizontal, 16)
        .frame(width: 393, height: 72)
        .background(CatPuzzleTheme.background)
        .environment(\.locale, Locale(identifier: "en"))

        try attach(content, name: name)
    }

    private func attach<Content: View>(_ content: Content, name: String) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let png = try XCTUnwrap(image.pngData())
        XCTAssertEqual(image.size, CGSize(width: 393, height: 72))
        XCTAssertGreaterThan(try opaquePixelCount(in: image), 393 * 72)

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func opaquePixelCount(in image: UIImage) throws -> Int {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: width * height * 4, by: 4).reduce(0) { count, index in
            count + (bytes[index] > 0 ? 1 : 0)
        }
    }
}

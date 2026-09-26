import CatPuzzleCore
import SwiftUI
import XCTest
@testable import CatPuzzle

/// Add a scene here to render another View. A model factory keeps each image
/// independent and lets the same test entry point cover different VM states.
@MainActor
private struct OffscreenScene {
    let name: String
    let size: CGSize
    let locale: Locale
    let background: Color
    let scale: CGFloat
    let makeView: () throws -> AnyView

    init<Content: View>(
        name: String,
        size: CGSize,
        locale: String = "en",
        background: Color = CatPuzzleTheme.background,
        scale: CGFloat = 2,
        view: @escaping () -> Content
    ) {
        self.name = name
        self.size = size
        self.locale = Locale(identifier: locale)
        self.background = background
        self.scale = scale
        makeView = { AnyView(view()) }
    }

    init<Model, Content: View>(
        name: String,
        size: CGSize,
        locale: String = "en",
        background: Color = CatPuzzleTheme.background,
        scale: CGFloat = 2,
        makeModel: @escaping () throws -> Model,
        view: @escaping (Model) -> Content
    ) {
        self.name = name
        self.size = size
        self.locale = Locale(identifier: locale)
        self.background = background
        self.scale = scale
        makeView = { AnyView(view(try makeModel())) }
    }
}

@MainActor
final class OffscreenRenderTests: XCTestCase {
    private static let canvas = CGSize(width: 393, height: 72)

    private static var scenes: [OffscreenScene] {
        [
            OffscreenScene(
                name: "six-region-status",
                size: canvas,
                makeModel: {
                    let fixture = OpeningLevels.fixtures[0]
                    var engine = try GameEngine(fixture: fixture, mode: .exploration)
                    for position in fixture.solution.prefix(2) {
                        try engine.setState(.cat, atRow: position.row, column: position.column)
                    }
                    return GameViewModel(engine: engine)
                },
                view: { model in
                    GameStatusBar(
                        regionIDs: model.regionIDs,
                        occupiedRegionIDs: model.occupiedRegionIDs,
                        remainingLives: model.remainingMistakes,
                        maxLives: model.level.maxMistakes
                    )
                    .padding(.horizontal, 16)
                }
            ),
            OffscreenScene(name: "ten-region-status", size: canvas) {
                GameStatusBar(
                    regionIDs: Array(0..<10),
                    occupiedRegionIDs: [0, 2, 5],
                    remainingLives: 1,
                    maxLives: 3
                )
                .padding(.horizontal, 16)
            },
            OffscreenScene(name: "compact-rule-strip-en", size: canvas) {
                RuleInfoStrip().padding(.horizontal, 16)
            },
            OffscreenScene(
                name: "compact-rule-strip-zh-Hans",
                size: canvas,
                locale: "zh-Hans"
            ) {
                RuleInfoStrip().padding(.horizontal, 16)
            },
        ]
    }

    func testRegisteredScenesRenderOffscreen() throws {
        for scene in Self.scenes {
            try XCTContext.runActivity(named: scene.name) { activity in
                let content = try scene.makeView()
                    .frame(width: scene.size.width, height: scene.size.height)
                    .background(scene.background)
                    .environment(\.locale, scene.locale)
                let renderer = ImageRenderer(content: content)
                renderer.scale = scene.scale
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size, scene.size)

                let backgroundOnly = Color.clear
                    .frame(width: scene.size.width, height: scene.size.height)
                    .background(scene.background)
                    .environment(\.locale, scene.locale)
                let baselineRenderer = ImageRenderer(content: backgroundOnly)
                baselineRenderer.scale = scene.scale
                let baseline = try XCTUnwrap(baselineRenderer.uiImage)
                XCTAssertNotEqual(
                    try pixelData(in: image),
                    try pixelData(in: baseline),
                    "\(scene.name) rendered only its background"
                )

                let png = try XCTUnwrap(image.pngData())
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = scene.name
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }

    private func pixelData(in image: UIImage) throws -> Data {
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
        return Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
    }
}

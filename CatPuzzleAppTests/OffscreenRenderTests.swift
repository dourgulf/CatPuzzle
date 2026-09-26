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
            OffscreenScene(name: "cell-marker-sizes", size: CGSize(width: 393, height: 100)) {
                HStack(spacing: 12) {
                    ForEach([32.0, 48.0, 64.0], id: \.self) { side in
                        HStack(spacing: 2) {
                            ForEach(0..<2, id: \.self) { index in
                                CellView(
                                    state: index == 0 ? .cat : .excluded,
                                    regionID: 1,
                                    row: 0,
                                    column: 0,
                                    cellSide: side,
                                    cornerRadius: 4,
                                    showsRegionIcon: false,
                                    isLocked: false,
                                    hintEmphasis: .normal,
                                    isMasked: false,
                                    isNudged: false,
                                    allowsInteraction: false,
                                    onTap: {},
                                    onToggleCatAccessibility: {}
                                )
                                .frame(width: side, height: side)
                            }
                        }
                    }
                }
            },
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
        ] + gameScenes + boardSpacingScenes
    }

    private static var boardSpacingScenes: [OffscreenScene] {
        [6, 7, 8, 9, 10, 12].map { size in
            OffscreenScene(
                name: "board-spacing-\(size)",
                size: CGSize(width: 393, height: 393),
                makeModel: {
                    try Puzzle(size: size, regionIDs: (0..<size).map { row in
                        (0..<size).map { column in (row + column / 3) % 10 }
                    })
                },
                view: { puzzle in
                    BoardView(
                        puzzle: puzzle, previewStates: [:], showsRegionIcons: false,
                        lockedPositions: [], hint: nil, appearance: .compact,
                        onTap: { _, _ in }, onDragSetExcluded: { _, _, _ in },
                        onToggleCatAccessibility: { _, _ in }
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .padding(4)
                }
            )
        }
    }

    private static var gameScenes: [OffscreenScene] {
        ["en", "zh-Hans"].flatMap { language in
            [(6, "normal", 320.0), (8, "hint", 393.0), (10, "normal", 393.0),
             (6, "solved", 320.0), (6, "failed", 320.0)].map { size, state, width in
                OffscreenScene(
                    name: "game-\(size)-\(state)-\(language)",
                    size: CGSize(width: width, height: 760),
                    locale: language,
                    makeModel: {
                        let fixture = try XCTUnwrap(BuiltInLevels.fixtures.first { $0.level.size == size })
                        var engine = try GameEngine(fixture: fixture, mode: .challenge)
                        if state == "solved" {
                            for position in fixture.solution {
                                try engine.setState(.cat, atRow: position.row, column: position.column)
                            }
                        }
                        let model = GameViewModel(engine: engine)
                        if state == "hint" { model.requestHint() }
                        if state == "failed" {
                            let wrong = try XCTUnwrap((0..<size).flatMap { row in
                                (0..<size).map { CellPosition(row: row, column: $0) }
                            }.first { !fixture.solution.contains($0) && !fixture.level.givenPositions.contains($0) })
                            for _ in 0..<fixture.level.maxMistakes {
                                model.toggleCat(atRow: wrong.row, column: wrong.column)
                            }
                            XCTAssertTrue(model.isFailed)
                        }
                        return model
                    },
                    view: { model in
                        let screen = GameScreen(
                            viewModel: model, presentation: .ladder(number: size),
                            showsRegionIcons: false, onBackToLevelStart: {},
                            onOpenSettings: {}, onContinue: {}
                        )
                        return Group {
                            if state == "solved" || state == "failed" {
                                screen
                            } else {
                                GamePlayContent(
                                    viewModel: model, presentation: .ladder(number: size),
                                    showsRegionIcons: false,
                                    onBackToLevelStart: {}, onOpenSettings: {}
                                )
                            }
                        }
                        .fontDesign(.rounded)
                        .foregroundStyle(CatPuzzleTheme.textPrimary)
                        .tint(CatPuzzleTheme.action)
                    }
                )
            }
        }
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

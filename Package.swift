// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CatPuzzle",
    products: [
        .library(name: "CatPuzzleCore", targets: ["CatPuzzleCore"]),
    ],
    targets: [
        .target(name: "CatPuzzleCore"),
        .testTarget(name: "CatPuzzleCoreTests", dependencies: ["CatPuzzleCore"]),
    ]
)

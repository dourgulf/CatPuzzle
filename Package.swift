// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CatPuzzle",
    products: [
        .library(name: "CatPuzzleCore", targets: ["CatPuzzleCore"]),
        .executable(name: "CatPuzzleGenerator", targets: ["CatPuzzleGenerator"]),
    ],
    targets: [
        .target(name: "CatPuzzleCore"),
        .executableTarget(name: "CatPuzzleGenerator", dependencies: ["CatPuzzleCore"]),
        .testTarget(name: "CatPuzzleCoreTests", dependencies: ["CatPuzzleCore"]),
    ]
)

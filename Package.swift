// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SkillsHub",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/QuentinHsu/SVGPath.git", branch: "main"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
    ],
    targets: [
        .executableTarget(
            name: "SkillsHub",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SVGPath", package: "SVGPath"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        )
    ]
)

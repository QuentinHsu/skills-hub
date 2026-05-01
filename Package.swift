// swift-tools-version: 6.1

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
    ],
    targets: [
        .executableTarget(
            name: "SkillsHub",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SVGPath", package: "SVGPath"),
            ],
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        )
    ]
)

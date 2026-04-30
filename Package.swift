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
    ],
    targets: [
        .executableTarget(
            name: "SkillsHub",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        )
    ]
)

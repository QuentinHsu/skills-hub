// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SkillsHub",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "SkillsHub",
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        )
    ]
)

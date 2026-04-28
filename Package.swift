// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SkillsHub",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "SkillsHub",
            path: "Sources"
        )
    ]
)

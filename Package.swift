// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GlossyBar",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4")
    ],
    targets: [
        .executableTarget(
            name: "GlossyBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/GlossyBar",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)

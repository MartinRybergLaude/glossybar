// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GlossyBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GlossyBar",
            path: "Sources/GlossyBar",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)

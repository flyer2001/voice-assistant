// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "voice",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "voice", targets: ["voice"]),
    ],
    targets: [
        .target(
            name: "voice",
            path: "Sources/voice"
        ),
        .testTarget(
            name: "voiceTests",
            dependencies: ["voice"],
            path: "Tests/voiceTests"
        ),
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "voice-ptt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoicePTT",
            path: "Sources/VoicePTT"
        )
    ]
)

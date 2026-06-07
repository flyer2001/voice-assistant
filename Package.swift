// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "voice-assistant",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "VoiceAssistant", targets: ["VoiceAssistant"]),
    ],
    targets: [
        .target(
            name: "VoiceAssistant",
            path: "Sources/VoiceAssistant"
        ),
        .testTarget(
            name: "VoiceAssistantTests",
            dependencies: ["VoiceAssistant"],
            path: "Tests/VoiceAssistantTests"
        ),
    ]
)

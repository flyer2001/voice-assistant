// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrivateVoiceMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "private-voice-mac", targets: ["PrivateVoiceMac"])],
    targets: [
        .target(name: "VoicePolicy"),
        .target(name: "PinnedAudio", linkerSettings: [
            .linkedFramework("AudioToolbox", .when(platforms: [.macOS])),
            .linkedFramework("CoreAudio", .when(platforms: [.macOS])),
            .linkedFramework("CoreFoundation", .when(platforms: [.macOS])),
        ]),
        .executableTarget(name: "PrivateVoiceMac", dependencies: [
            "VoicePolicy", .target(name: "PinnedAudio", condition: .when(platforms: [.macOS]))
        ]),
        .testTarget(name: "VoicePolicyTests", dependencies: ["VoicePolicy"]),
    ],
    swiftLanguageModes: [.v5]
)

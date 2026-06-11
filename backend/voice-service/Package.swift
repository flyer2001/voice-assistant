// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "voice-service",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "voice-service", targets: ["VoiceService"]),
        .library(name: "VoiceServiceCore", targets: ["VoiceServiceCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "VoiceServiceCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .executableTarget(
            name: "VoiceService",
            dependencies: ["VoiceServiceCore"]
        ),
        .testTarget(
            name: "VoiceServiceCoreTests",
            dependencies: [
                "VoiceServiceCore",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)

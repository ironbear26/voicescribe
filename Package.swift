// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceScribe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoiceScribe",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)

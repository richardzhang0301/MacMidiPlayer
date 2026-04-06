// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacMidiPlayer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MacMidiPlayer",
            path: "Sources/MacMidiPlayer",
            linkerSettings: [
                .linkedFramework("CoreMIDI"),
                .linkedFramework("AudioToolbox"),
            ]
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XNoise",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "XNoise",
            path: "Sources/XNoise",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/XNoise/Resources/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "XNoiseTests",
            dependencies: ["XNoise"],
            path: "Tests/XNoiseTests",
            resources: [.process("Fixtures")]
        ),
    ]
)

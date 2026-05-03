// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shuuchuu",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Shuuchuu",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Shuuchuu",
            exclude: ["Resources/Info.plist"],
            resources: [.process("Resources")],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Shuuchuu/Resources/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "ShuuchuuTests",
            dependencies: ["Shuuchuu"],
            path: "Tests/ShuuchuuTests",
            resources: [.process("Fixtures")]
        ),
    ]
)

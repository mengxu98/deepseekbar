// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DeepSeekBar", targets: ["DeepSeekBar"])
    ],
    targets: [
        .executableTarget(
            name: "DeepSeekBar",
            path: "Sources/DeepSeekBar",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "DeepSeekBarTests",
            dependencies: ["DeepSeekBar"],
            path: "Tests/DeepSeekBarTests"
        )
    ]
)

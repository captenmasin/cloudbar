// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "CloudBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "CloudBar",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "CloudBarTests",
            dependencies: ["CloudBar"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "CloudBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CloudBar",
            resources: [
                .copy("Resources/AppInfo.plist"),
                .copy("Resources/AppIcon.png"),
                .copy("Resources/logo.svg"),
            ],
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

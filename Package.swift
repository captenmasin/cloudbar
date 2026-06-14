// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloudBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CloudBar",
            exclude: [
                "Resources/CloudBar.entitlements",
            ],
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

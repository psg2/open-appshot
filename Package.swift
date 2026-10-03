// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenAppShot",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "OpenAppShot", targets: ["OpenAppShot"])],
    targets: [
        .target(
            name: "OpenAppShotCore",
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .executableTarget(
            name: "OpenAppShot",
            dependencies: ["OpenAppShotCore"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "OpenAppShotCoreTests",
            dependencies: ["OpenAppShotCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)

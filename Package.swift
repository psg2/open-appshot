// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenAppShot",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "OpenAppShot", targets: ["OpenAppShot"])],
    targets: [
        .executableTarget(
            name: "OpenAppShot",
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        )
    ],
    swiftLanguageModes: [.v5]
)

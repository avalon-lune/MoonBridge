// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MoonBridge",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MoonBridge", targets: ["MoonBridge"])],
    targets: [
        .target(name: "MoonBridgeCore"),
        .executableTarget(name: "MoonBridge", dependencies: ["MoonBridgeCore"]),
        .executableTarget(name: "MoonBridgeCheck", dependencies: ["MoonBridgeCore"], path: "tests/Check")
    ],
    swiftLanguageVersions: [.v5]
)

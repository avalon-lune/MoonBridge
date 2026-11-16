// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "MoonBridge",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MoonBridge", targets: ["MoonBridge"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "MoonBridgeCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MoonBridge", dependencies: ["MoonBridgeCore"]),
        .executableTarget(name: "MoonBridgeCheck", dependencies: ["MoonBridgeCore"], path: "tests/Check"),
        .executableTarget(name: "MoonBridgeCompanionCheck", dependencies: ["MoonBridgeCore"], path: "tests/Companion"),
        .executableTarget(name: "MoonBridgeMemoryCheck", dependencies: ["MoonBridgeCore"], path: "tests/Memory")
    ],
    swiftLanguageVersions: [.v5]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Luma",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Luma", targets: ["Luma"]),
        .library(name: "LumaCore", targets: ["LumaCore"])
    ],
    targets: [
        .target(name: "LumaCore"),
        .executableTarget(name: "Luma", dependencies: ["LumaCore"]),
        .testTarget(name: "LumaCoreTests", dependencies: ["LumaCore"])
    ],
    swiftLanguageModes: [.v5]
)

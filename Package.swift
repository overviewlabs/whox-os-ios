// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WHOXOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "WHOXCore", targets: ["WHOXCore"])
    ],
    targets: [
        .target(name: "WHOXCore"),
        .testTarget(name: "WHOXCoreTests", dependencies: ["WHOXCore"])
    ]
)

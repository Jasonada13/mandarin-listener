// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MandarinListenerCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "MandarinListenerCore", targets: ["MandarinListenerCore"])
    ],
    targets: [
        .target(name: "MandarinListenerCore"),
        .testTarget(
            name: "MandarinListenerCoreTests",
            dependencies: ["MandarinListenerCore"]
        )
    ]
)

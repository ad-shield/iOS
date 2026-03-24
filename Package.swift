// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AdShield",
    platforms: [
        .iOS(.v13),
        .macOS(.v12),
    ],
    products: [
        .library(name: "AdShield", targets: ["AdShield"]),
    ],
    targets: [
        .target(name: "AdShield"),
        .testTarget(name: "AdShieldTests", dependencies: ["AdShield"]),
    ]
)

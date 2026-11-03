// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZentoExtensionKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZentoExtensionProtocol", targets: ["ZentoExtensionProtocol"]),
        .library(name: "ZentoExtensionSDK", targets: ["ZentoExtensionSDK"])
    ],
    targets: [
        .target(name: "ZentoExtensionProtocol"),
        .target(name: "ZentoExtensionSDK", dependencies: ["ZentoExtensionProtocol"])
    ]
)

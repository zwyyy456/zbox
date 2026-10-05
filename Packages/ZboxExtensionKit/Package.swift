// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ZboxExtensionKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZboxExtensionProtocol", targets: ["ZboxExtensionProtocol"]),
        .library(name: "ZboxExtensionSDK", targets: ["ZboxExtensionSDK"])
    ],
    targets: [
        .target(name: "ZboxExtensionProtocol"),
        .target(name: "ZboxExtensionSDK", dependencies: ["ZboxExtensionProtocol"])
    ]
)

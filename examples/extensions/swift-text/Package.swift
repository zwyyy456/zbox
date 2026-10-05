// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TextCaseExtension",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../../Packages/ZboxExtensionKit")],
    targets: [.executableTarget(name: "TextCaseExtension",
        dependencies: [.product(name: "ZboxExtensionSDK", package: "ZboxExtensionKit")], path: "Sources")]
)

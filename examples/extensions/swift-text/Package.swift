// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TextCaseExtension",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../../Packages/ZentoExtensionKit")],
    targets: [.executableTarget(name: "TextCaseExtension",
        dependencies: [.product(name: "ZentoExtensionSDK", package: "ZentoExtensionKit")], path: "Sources")]
)

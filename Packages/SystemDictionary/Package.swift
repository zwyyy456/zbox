// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SystemDictionary", platforms: [.macOS(.v15)], products: [
    .library(name: "SystemDictionary", targets: ["SystemDictionary"])
], targets: [
    .target(name: "SystemDictionaryBridge", linkerSettings: [.linkedFramework("CoreServices")]),
    .target(name: "SystemDictionary", dependencies: ["SystemDictionaryBridge"]),
    .testTarget(name: "SystemDictionaryTests", dependencies: ["SystemDictionary"])
])

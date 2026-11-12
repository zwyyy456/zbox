// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CGIF",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CGIF", type: .static, targets: ["CGIF"])],
    targets: [.target(name: "CGIF")],
    cLanguageStandard: .c99
)

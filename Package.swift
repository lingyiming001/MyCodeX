// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DeskGPT", platforms: [.macOS(.v14)], products: [.executable(name: "DeskGPT", targets: ["DeskGPT"])], targets: [.executableTarget(name: "DeskGPT")], swiftLanguageModes: [.v5])

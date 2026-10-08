// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ribbon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Ribbon", path: "Sources/Ribbon")
    ],
    swiftLanguageModes: [.v5]
)

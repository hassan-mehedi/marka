// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "marka",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Marka"),
        .testTarget(name: "MarkaTests", dependencies: ["Marka"])
    ]
)

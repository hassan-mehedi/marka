// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "marka",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages", from: "0.1.9"),
    ],
    targets: [
        .executableTarget(
            name: "Marka",
            dependencies: [
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
            ]
        ),
        .testTarget(name: "MarkaTests", dependencies: ["Marka"])
    ]
)

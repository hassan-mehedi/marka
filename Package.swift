// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "marka",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages", from: "0.1.9"),
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.7.3"),
    ],
    targets: [
        .executableTarget(
            name: "Marka",
            dependencies: [
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
                .product(name: "SwiftMath", package: "SwiftMath"),
            ],
            resources: [
                .copy("Resources/mermaid.min.js"),
            ]
        ),
        .testTarget(name: "MarkaTests", dependencies: ["Marka"])
    ]
)

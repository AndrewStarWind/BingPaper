// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BingPaper",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "BingPaperCore", targets: ["BingPaperCore"]),
        .executable(name: "BingPaper", targets: ["BingPaperApp"])
    ],
    targets: [
        .target(
            name: "BingPaperCore",
            path: "Sources/BingPaperCore"
        ),
        .executableTarget(
            name: "BingPaperApp",
            dependencies: ["BingPaperCore"],
            path: "Sources/BingPaperApp"
        ),
        .testTarget(
            name: "BingPaperCoreTests",
            dependencies: ["BingPaperCore"],
            path: "Tests/BingPaperCoreTests"
        )
    ]
)

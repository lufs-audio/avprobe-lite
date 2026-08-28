// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "avprobe-lite",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // 1.2.0 requires macOS 12+; our probing and the CLI run on macOS 13+.
        // swift-argument-parser is referenced explicitly at .product so the
        // executable links only what it uses.
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.2.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "avprobe-lite",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/avprobe-lite"
        ),
        .testTarget(
            name: "avprobe-liteTests",
            dependencies: ["avprobe-lite"],
            path: "Tests/avprobe-liteTests"
        )
    ]
)

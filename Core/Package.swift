// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PhotoSiftCore", targets: ["PhotoSiftCore"]),
        .library(name: "PhotoSiftTestSupport", targets: ["PhotoSiftTestSupport"]),
    ],
    targets: [
        .target(name: "PhotoSiftCore"),
        .target(name: "PhotoSiftTestSupport", dependencies: ["PhotoSiftCore"]),
        .testTarget(
            name: "PhotoSiftCoreTests",
            dependencies: ["PhotoSiftCore", "PhotoSiftTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

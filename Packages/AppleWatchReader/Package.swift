// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleWatchReader",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AppleWatchReader", targets: ["AppleWatchReader"]),
    ],
    targets: [
        .target(name: "AppleWatchReader"),
    ]
)

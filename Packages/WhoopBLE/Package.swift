// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhoopBLE",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "WhoopBLE", targets: ["WhoopBLE"]),
    ],
    dependencies: [
        .package(path: "../WhoopProtocol"),
    ],
    targets: [
        .target(
            name: "WhoopBLE",
            dependencies: [
                .product(name: "WhoopProtocol", package: "WhoopProtocol"),
            ]
        ),
    ]
)

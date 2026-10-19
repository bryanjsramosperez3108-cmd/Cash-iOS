// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Taxes",
platforms: [
    .iOS("26.0"),
    .macOS(.v14)
],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "Taxes",
            targets: ["Taxes"]
        ),
    ],
    targets: [
        .target(
            name: "Taxes"
        ),
    ]
)

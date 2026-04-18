// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CalorieEstimator",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "CalorieEstimator",
            targets: ["CalorieEstimator"]
        )
    ],
    targets: [
        .target(name: "CalorieEstimator")
    ]
)

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CalorieEstimator",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "CalorieEstimator",
            targets: ["CalorieEstimator"]
        )
    ],
    targets: [
        .target(
            name: "CalorieEstimator",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "CalorieEstimatorTests",
            dependencies: ["CalorieEstimator"],
            resources: [.process("Resources")]
        )
    ]
)

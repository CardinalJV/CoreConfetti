// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreConfetti",
    // UIKit under the hood: iOS and the platforms that carry UIKit with them.
    platforms: [
        .iOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "CoreConfetti", targets: ["CoreConfetti"])
    ],
    targets: [
        .target(name: "CoreConfetti"),
        .testTarget(name: "CoreConfettiTests", dependencies: ["CoreConfetti"])
    ]
)

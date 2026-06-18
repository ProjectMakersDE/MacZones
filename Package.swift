// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacZones",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MacZones",
            path: "Sources/MacZones"
        ),
        .testTarget(
            name: "MacZonesTests",
            dependencies: ["MacZones"],
            path: "Tests/MacZonesTests"
        )
    ]
)

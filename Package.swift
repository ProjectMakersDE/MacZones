// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Maxons",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Maxons",
            path: "Sources/Maxons"
        )
    ]
)

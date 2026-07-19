// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Berth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Berth",
            path: "Sources/Berth"
        ),
    ]
)

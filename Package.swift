// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BackdropPlayer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BackdropPlayer", targets: ["BackdropPlayer"])
    ],
    targets: [
        .executableTarget(
            name: "BackdropPlayer",
            path: "Sources"
        )
    ]
)

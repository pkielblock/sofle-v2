// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sofle",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Sofle", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SofleTests", dependencies: ["Sofle"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Readout",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Readout", path: "Sources/Readout")
    ]
)

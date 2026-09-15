// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TextViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TextViewer", path: "Sources/TextViewer")
    ]
)

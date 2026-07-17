// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceDeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoiceDeck", targets: ["VoiceDeck"])
    ],
    targets: [
        .executableTarget(name: "VoiceDeck")
    ]
)

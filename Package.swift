// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Brew",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Brew", targets: ["Brew"])],
    targets: [
        .target(name: "BrewKit"),
        .executableTarget(name: "Brew", dependencies: ["BrewKit"]),
        .testTarget(name: "BrewTests", dependencies: ["BrewKit"])
    ]
)

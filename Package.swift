// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "QuickLaunch", platforms: [.macOS(.v13)],
    products: [.executable(name: "QuickLaunch", targets: ["QuickLaunch"])],
    targets: [
        .target(name: "QuickLaunchCore"),
        .executableTarget(name: "QuickLaunch", dependencies: ["QuickLaunchCore"]),
        .testTarget(name: "QuickLaunchCoreTests", dependencies: ["QuickLaunchCore"])
    ])

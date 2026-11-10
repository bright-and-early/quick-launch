// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "QuickLaunch", platforms: [.macOS(.v13)],
    products: [.executable(name: "QuickLaunch", targets: ["QuickLaunch"])],
    targets: [
        .target(name: "QuickLaunchCore"),
        .target(name: "QuickLaunchUI", dependencies: ["QuickLaunchCore"]),
        .executableTarget(name: "QuickLaunch", dependencies: ["QuickLaunchCore", "QuickLaunchUI"]),
        .executableTarget(name: "InteractionChecks", dependencies: ["QuickLaunchCore", "QuickLaunchUI"], path: "Tests/InteractionChecks"),
        .executableTarget(name: "CoreChecks", dependencies: ["QuickLaunchCore"], path: "Tests/CoreChecks")
    ])

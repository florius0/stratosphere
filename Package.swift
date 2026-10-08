// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stratosphere",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "UI", targets: ["UI"]),
        .executable(name: "StoryCatalog", targets: ["StoryCatalog"]),
        .executable(name: "FixtureApp", targets: ["FixtureApp"]),
        .executable(name: "EnvironmentProbe", targets: ["EnvironmentProbe"]),
    ],
    targets: [
        .target(name: "Domain"),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .target(name: "UI"),
        .executableTarget(name: "StoryCatalog", dependencies: ["UI"]),
        .testTarget(name: "UITests", dependencies: ["UI"]),
        .executableTarget(name: "FixtureApp"),
        .target(name: "DisplayProbeBridge", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("Foundation")]),
        .executableTarget(name: "EnvironmentProbe", dependencies: ["DisplayProbeBridge"]),
        .testTarget(name: "EnvironmentProbeTests", dependencies: ["EnvironmentProbe"]),
    ],
    swiftLanguageModes: [.v6]
)

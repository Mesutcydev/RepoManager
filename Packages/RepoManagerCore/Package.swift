// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RepoManagerCore",
    platforms: [.iOS("26.0"), .macOS("26.0"), .macCatalyst("26.0")],
    products: [.library(name: "RepoManagerCore", targets: ["RepoManagerCore"]),.executable(name:"RepoManagerCatalog",targets:["RepoManagerCatalog"])],
    dependencies: [.package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.11.0")],
    targets: [
        .target(name: "RepoManagerCore", dependencies: [.product(name: "Sodium", package: "swift-sodium")]),
        .executableTarget(name:"RepoManagerCatalog",dependencies:["RepoManagerCore"]),
        .testTarget(name: "RepoManagerCoreTests", dependencies: ["RepoManagerCore"])
    ],
    swiftLanguageModes: [.v6]
)

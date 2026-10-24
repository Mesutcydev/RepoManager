// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RepoManagerUI", defaultLocalization: "en", platforms: [.iOS("26.0"), .macCatalyst("26.0")],
    products: [.library(name: "RepoManagerUI", targets: ["RepoManagerUI"])],
    dependencies: [.package(path: "../RepoManagerCore")],
    targets: [.target(name: "RepoManagerUI", dependencies: ["RepoManagerCore"], resources: [.process("Resources")])],
    swiftLanguageModes: [.v6]
)

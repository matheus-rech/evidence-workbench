// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EvidenceWorkbench",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReviewCore", targets: ["ReviewCore"]),
        .executable(name: "EvidenceWorkbench", targets: ["EvidenceWorkbench"])
    ],
    targets: [
        .target(name: "ReviewCore"),
        .executableTarget(name: "EvidenceWorkbench", dependencies: ["ReviewCore"]),
        .testTarget(name: "ReviewCoreTests", dependencies: ["ReviewCore"]),
        .testTarget(name: "WorkbenchIntegrationTests", dependencies: ["EvidenceWorkbench", "ReviewCore"])
    ]
)

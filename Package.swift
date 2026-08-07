// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OkTally",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "OkTally",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "OkTallyTests",
            dependencies: ["OkTally"],
            resources: [.copy("Fixtures")]
        )
    ]
)

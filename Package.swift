// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OkTally",
    defaultLocalization: "pt",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "OkTally",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OkTallyTests",
            dependencies: [
                "OkTally",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)

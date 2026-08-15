// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OkTally",
    defaultLocalization: "pt",
    platforms: [.macOS(.v26)],
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
    ],
    // Tools-version 6.2 (exigido por .v26) muda o modo de linguagem padrão para Swift 6;
    // fixamos em Swift 5 aqui para não misturar a subida de deployment target com uma
    // migração de concorrência estrita, que é fora do escopo desta task.
    swiftLanguageModes: [.v5]
)

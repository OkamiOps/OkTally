// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OkTally",
    defaultLocalization: "pt",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        // Exceção documentada à regra de "nenhuma dependência nova": o painel do notch.
        // Ver .superpowers/notch-hud-report.md.
        //
        // VENDORADO (era o 1.1.0 do GitHub, MIT) por causa de um limite do pacote que não
        // dá para contornar por fora: o painel compacto tem exatamente a altura do notch
        // físico, então a barra contínua do rodapé passava POR TRÁS do recorte — no
        // framebuffer ela era uma só, mas o hardware engolia o miolo e o olho via dois
        // tocos. O patch (marcado com "[OkTally patch]") acrescenta `compactBottomShelf`:
        // uma prateleira de altura configurável abaixo do notch, onde a barra ganha
        // pixels reais de ponta a ponta.
        .package(path: "Vendor/DynamicNotchKit")
    ],
    targets: [
        .executableTarget(
            name: "OkTally",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit")
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

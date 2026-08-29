import XCTest
@testable import OkTally

final class ProviderOrderTests: XCTestCase {
    private let defaults = [
        "claude", "codex", "supergrok", "cursor", "cursor-grokbot", "copilot",
        "antigravity", "openrouter", "minimax", "opencode", "mimo"
    ]
    private let known = [
        "claude", "codex", "openrouter", "minimax", "cursor", "cursor-grokbot",
        "copilot", "antigravity", "opencode", "mimo", "supergrok"
    ]

    func test_nadaSalvo_usaAOrdemHistoricaDasPreferenciasNaoADoRegistry() {
        XCTAssertEqual(ProviderOrder.resolved(saved: [], known: known), defaults)
    }

    func test_listaSalva_filtraIdsDesconhecidosEPreservaAOrdemDoDono() {
        XCTAssertEqual(
            ProviderOrder.resolved(saved: ["mimo", "ghost", "claude"], known: ["claude", "mimo", "codex"]),
            ["mimo", "claude", "codex"]
        )
    }

    func test_providerNovo_entraNoFimNaOrdemDoRegistry() {
        XCTAssertEqual(
            ProviderOrder.resolved(saved: ["mimo", "claude"], known: ["claude", "novo", "mimo", "outro"]),
            ["mimo", "claude", "novo", "outro"]
        )
    }

    func test_duplicataNaListaSalva_mantemAPrimeira() {
        XCTAssertEqual(
            ProviderOrder.resolved(saved: ["claude", "mimo", "claude"], known: ["claude", "mimo"]),
            ["claude", "mimo"]
        )
    }
}

import XCTest
@testable import OkTally

/// Cobre a composição do auto-save das Preferências: a guarda, o parser de cada campo e o
/// texto para o qual o campo volta quando a edição é recusada. O `FieldCommitTests` prova
/// as regras isoladas; aqui o que se prova é o cenário da tela — "limpei o campo, saí do
/// campo, o valor salvo sobreviveu".
final class PreferencesFieldCommitTests: XCTestCase {

    // MARK: - Chaves de API

    func test_campoVazioNaoApagaAChaveSalva() {
        // O cenário: usuário seleciona tudo, apaga sem querer e clica fora.
        XCTAssertEqual(PreferencesFieldCommit.secret(raw: "", saved: "sk-abc"),
                       .ignored(restore: "sk-abc"))
        XCTAssertEqual(PreferencesFieldCommit.secret(raw: "   ", saved: "sk-abc"),
                       .ignored(restore: "sk-abc"))
    }

    func test_valorInalteradoNaoGravaDeNovo() {
        XCTAssertEqual(PreferencesFieldCommit.secret(raw: "sk-abc", saved: "sk-abc"),
                       .ignored(restore: "sk-abc"))
        XCTAssertEqual(PreferencesFieldCommit.secret(raw: " sk-abc ", saved: "sk-abc"),
                       .ignored(restore: "sk-abc"))
    }

    func test_chaveNovaGravaOValorSaneado() {
        // Espaços de um paste não vão para o Keychain.
        XCTAssertEqual(PreferencesFieldCommit.secret(raw: "  sk-novo  ", saved: "sk-abc"),
                       .commit(value: "sk-novo", display: "sk-novo"))
    }

    func test_campoVazioSemChaveSalvaContinuaVazio() {
        XCTAssertEqual(PreferencesFieldCommit.secret(raw: "", saved: ""),
                       .ignored(restore: ""))
    }

    // MARK: - Franquia do MiMo

    func test_franquiaVaziaNaoApagaOValorSalvo() {
        // O bug que esta task tinha de fechar: `= Double(mimoAllowance)` com campo vazio
        // gravava `nil` e apagava a franquia.
        XCTAssertEqual(PreferencesFieldCommit.allowance(raw: "", saved: 500),
                       .ignored(restore: "500.0"))
        XCTAssertEqual(PreferencesFieldCommit.allowance(raw: "   ", saved: 500),
                       .ignored(restore: "500.0"))
    }

    func test_franquiaComLixoNaoApagaOValorSalvo() {
        XCTAssertEqual(PreferencesFieldCommit.allowance(raw: "abc", saved: 500),
                       .ignored(restore: "500.0"))
        XCTAssertEqual(PreferencesFieldCommit.allowance(raw: "1e3", saved: 500),
                       .ignored(restore: "500.0"))
        XCTAssertEqual(PreferencesFieldCommit.allowance(raw: "inf", saved: 500),
                       .ignored(restore: "500.0"))
    }

    func test_franquiaAceitaVirgulaEGravaOTextoQueOCampoMostra() {
        XCTAssertEqual(PreferencesFieldCommit.allowance(raw: "750,5", saved: 500),
                       .commit(value: 750.5, display: "750.5"))
    }

    func test_franquiaZeroERecusada() {
        // Franquia zero não mede nada — e recusá-la não pode apagar a que está salva.
        XCTAssertEqual(PreferencesFieldCommit.allowance(raw: "0", saved: 500),
                       .ignored(restore: "500.0"))
    }

    func test_franquiaInalteradaNaoRegrava() {
        // `display` e o texto de `load()` saem do mesmo `credits`, então o commit seguinte
        // reconhece o valor como inalterado em vez de gravar de novo a cada blur.
        guard case .commit(_, let display) = PreferencesFieldCommit.allowance(raw: "750,5", saved: 500) else {
            return XCTFail("esperava commit")
        }
        XCTAssertEqual(PreferencesFieldCommit.allowance(raw: display, saved: 750.5),
                       .ignored(restore: display))
    }

    // MARK: - Créditos usados

    func test_usadosVaziosNaoApagamOValorSalvo() {
        XCTAssertEqual(PreferencesFieldCommit.used(raw: "", saved: 123),
                       .ignored(restore: "123.0"))
    }

    func test_usadosAceitamZero() {
        // Mês recém-começado: zero é legítimo aqui, ao contrário da franquia.
        XCTAssertEqual(PreferencesFieldCommit.used(raw: "0", saved: 123),
                       .commit(value: 0, display: "0.0"))
    }

    func test_usadosRecusamNegativoInfinitoELixo() {
        XCTAssertEqual(PreferencesFieldCommit.used(raw: "-5", saved: 123), .ignored(restore: "123.0"))
        XCTAssertEqual(PreferencesFieldCommit.used(raw: "inf", saved: 123), .ignored(restore: "123.0"))
        XCTAssertEqual(PreferencesFieldCommit.used(raw: "nan", saved: 123), .ignored(restore: "123.0"))
        XCTAssertEqual(PreferencesFieldCommit.used(raw: "abc", saved: 123), .ignored(restore: "123.0"))
    }
}

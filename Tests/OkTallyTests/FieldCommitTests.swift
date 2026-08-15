import XCTest
@testable import OkTally

final class FieldCommitTests: XCTestCase {
    func test_trimsBeforePersisting() {
        XCTAssertEqual(FieldCommit.sanitized("  sk-abc  ", previous: ""), "sk-abc")
    }

    func test_emptyFieldNeverWipesTheStoredCredential() {
        // O risco declarado no spec: auto-save no blur não pode apagar a chave existente.
        XCTAssertNil(FieldCommit.sanitized("", previous: "sk-abc"))
        XCTAssertNil(FieldCommit.sanitized("   ", previous: "sk-abc"))
    }

    func test_unchangedValueDoesNotTriggerAWrite() {
        XCTAssertNil(FieldCommit.sanitized("sk-abc", previous: "sk-abc"))
        XCTAssertNil(FieldCommit.sanitized(" sk-abc ", previous: "sk-abc"))
    }

    func test_lowBalanceAcceptsDotAndComma() {
        // pt-BR digita 5,00 — rejeitar isso viraria "não salva e não explica".
        XCTAssertEqual(FieldCommit.lowBalance("5.50"), 5.5)
        XCTAssertEqual(FieldCommit.lowBalance("5,50"), 5.5)
        XCTAssertEqual(FieldCommit.lowBalance(" 12 "), 12)
    }

    func test_lowBalanceRejectsNonPositiveAndGarbage() {
        XCTAssertNil(FieldCommit.lowBalance("0"))
        XCTAssertNil(FieldCommit.lowBalance("-3"))
        XCTAssertNil(FieldCommit.lowBalance("abc"))
        XCTAssertNil(FieldCommit.lowBalance(""))
    }

    func test_amountAcceptsZeroButRejectsNegativesAndGarbage() {
        // Os créditos "usados" do MiMo começam em zero — recusar 0 como o saldo baixo faz
        // deixaria o campo impossível de zerar.
        XCTAssertEqual(FieldCommit.amount("0"), 0)
        XCTAssertEqual(FieldCommit.amount(" 40,5 "), 40.5)
        XCTAssertNil(FieldCommit.amount("-1"))
        XCTAssertNil(FieldCommit.amount("abc"))
        XCTAssertNil(FieldCommit.amount(""))
        XCTAssertNil(FieldCommit.amount("1e3"))
        // "inf" e "nan" passam por `Double(_:)` — infinito gravado em disco viraria uma
        // barra de cota sem sentido.
        XCTAssertNil(FieldCommit.amount("inf"))
        XCTAssertNil(FieldCommit.amount("-inf"))
        XCTAssertNil(FieldCommit.amount("nan"))
        XCTAssertNil(FieldCommit.lowBalance("inf"))
    }

    func test_lowBalanceRejectsScientificNotation() {
        // "1e3" vira 1000.0 silenciosamente com Double(_:) puro — um limiar de alerta
        // errado, digitado ou colado por engano, sem nenhum sinal de erro.
        XCTAssertNil(FieldCommit.lowBalance("1e3"))
        XCTAssertNil(FieldCommit.lowBalance("2E-1"))
    }
}

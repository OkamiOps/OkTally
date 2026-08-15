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
}

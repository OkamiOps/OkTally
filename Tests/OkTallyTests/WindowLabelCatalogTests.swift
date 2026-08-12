// Tests/OkTallyTests/WindowLabelCatalogTests.swift
import XCTest
@testable import OkTally

final class WindowLabelCatalogTests: XCTestCase {
    func test_exactMatches_translateToFriendlyPortuguese() {
        XCTAssertEqual(WindowLabelCatalog.displayLabel("5h"), "Sessão 5h")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("weekly"), "Semanal")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("weekly-opus"), "Opus semanal")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("semanal"), "Semanal")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("uso"), "Uso")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("balance"), "Saldo")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("percent"), "Ciclo")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("mensal"), "Mensal")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("monthly"), "Mensal")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("plano"), "Plano")
    }

    func test_copilotLabels_translate() {
        XCTAssertEqual(WindowLabelCatalog.displayLabel("chat"), "Chat")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("completions"), "Autocomplete")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("premium"), "Premium")
    }

    func test_parenthesizedSuffix_translatesOnlyTheWindowKind() {
        XCTAssertEqual(
            WindowLabelCatalog.displayLabel("GPT-5.3-Codex-Spark (weekly)"),
            "GPT-5.3-Codex-Spark (Semanal)"
        )
        XCTAssertEqual(
            WindowLabelCatalog.displayLabel("GPT-5.3-Codex-Spark (semanal)"),
            "GPT-5.3-Codex-Spark (Semanal)"
        )
    }

    func test_unknownLabels_passThroughUnchanged() {
        XCTAssertEqual(WindowLabelCatalog.displayLabel("3d"), "3d")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("algo (desconhecido)"), "algo (desconhecido)")
        XCTAssertEqual(WindowLabelCatalog.displayLabel(""), "")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("()"), "()")
    }
}

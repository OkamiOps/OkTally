// Tests/OkTallyTests/WindowLabelCatalogTests.swift
import XCTest
@testable import OkTally

final class WindowLabelCatalogTests: XCTestCase {
    func test_exactMatches_translateToFriendlyDisplayNames() {
        XCTAssertEqual(WindowLabelCatalog.displayLabel("5h"), L("Sessão 5h"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("weekly"), L("Semanal"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("weekly-opus"), L("Opus semanal"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("semanal"), L("Semanal"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("uso"), L("Uso"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("balance"), L("Saldo"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("percent"), L("Ciclo"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("mensal"), L("Mensal"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("monthly"), L("Mensal"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("plano"), L("Plano"))
    }

    func test_copilotLabels_translate() {
        XCTAssertEqual(WindowLabelCatalog.displayLabel("chat"), L("Chat"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("completions"), L("Autocomplete"))
        XCTAssertEqual(WindowLabelCatalog.displayLabel("premium"), L("Premium"))
    }

    func test_parenthesizedSuffix_translatesOnlyTheWindowKind() {
        XCTAssertEqual(
            WindowLabelCatalog.displayLabel("GPT-5.3-Codex-Spark (weekly)"),
            "GPT-5.3-Codex-Spark (\(L("Semanal")))"
        )
        XCTAssertEqual(
            WindowLabelCatalog.displayLabel("GPT-5.3-Codex-Spark (semanal)"),
            "GPT-5.3-Codex-Spark (\(L("Semanal")))"
        )
    }

    func test_unknownLabels_passThroughUnchanged() {
        XCTAssertEqual(WindowLabelCatalog.displayLabel("3d"), "3d")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("algo (desconhecido)"), "algo (desconhecido)")
        XCTAssertEqual(WindowLabelCatalog.displayLabel(""), "")
        XCTAssertEqual(WindowLabelCatalog.displayLabel("()"), "()")
    }
}

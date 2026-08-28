import XCTest
@testable import OkTally

/// O contrato da preferência do alvo da previsão: a escolha é persistível, mas não
/// conhece nem resolve janelas — isso continua sendo responsabilidade do engine.
final class ForecastSlotTests: XCTestCase {
    func test_storedRoundTrip() {
        XCTAssertEqual(ForecastSlot(stored: ForecastSlot.automatic.stored), .automatic)

        let explicit = ForecastSlot.window(providerId: "claude", windowLabel: "5h")
        XCTAssertEqual(ForecastSlot(stored: explicit.stored), explicit)
    }

    func test_invalidStoredValuesFallBackToAutomatic() {
        XCTAssertEqual(ForecastSlot(stored: nil), .automatic)
        XCTAssertEqual(ForecastSlot(stored: ""), .automatic)
        XCTAssertEqual(ForecastSlot(stored: "sem-separador"), .automatic)
        XCTAssertEqual(ForecastSlot(stored: "claude\u{1}"), .automatic)
        XCTAssertEqual(ForecastSlot(stored: "\u{1}5h"), .automatic)
    }

    func test_storedLabelKeepsEverythingAfterTheFirstSeparator() {
        XCTAssertEqual(
            ForecastSlot(stored: "claude\u{1}a\u{1}b"),
            .window(providerId: "claude", windowLabel: "a\u{1}b")
        )
    }
}

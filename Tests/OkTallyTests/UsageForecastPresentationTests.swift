// Tests/OkTallyTests/UsageForecastPresentationTests.swift
import XCTest
@testable import OkTally

final class UsageForecastPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3_600

    private func forecast(
        state: UsageForecastState,
        usedPercent: Double = 27,
        exhaustionInHours: Double? = 12,
        resetInHours: Double? = 24,
        ratePerDay: Double? = 14.2,
        safeRatePerDay: Double? = 11.8,
        gap: TimeInterval? = nil
    ) -> UsageForecast {
        UsageForecast(
            id: ForecastWindowID(providerId: "cursor-grokbot", windowLabel: "weekly"),
            cadence: .weekly,
            currentUsedPercent: usedPercent,
            samples: [],
            ratePerDay: ratePerDay,
            safeRatePerDay: safeRatePerDay,
            exhaustionAt: exhaustionInHours.map { now.addingTimeInterval($0 * hour) },
            resetAt: resetInHours.map { now.addingTimeInterval($0 * hour) },
            gap: gap,
            state: state
        )
    }

    func test_headlinesEmPortuguesExplicamCadaEstadoSemPrometerCerteza() {
        XCTAssertEqual(
            UsageForecastPresentation(
                forecast: forecast(state: .slowDown, gap: 36 * hour), now: now
            ).headline,
            "Desacelere · pode acabar 1d 12h antes"
        )
        XCTAssertEqual(
            UsageForecastPresentation(forecast: forecast(state: .onPace), now: now).headline,
            "No ritmo certo · chega perto da renovação"
        )
        XCTAssertEqual(
            UsageForecastPresentation(
                forecast: forecast(state: .canAccelerate, gap: -30 * hour), now: now
            ).headline,
            "Pode acelerar · chega com 1d 6h de folga"
        )
        XCTAssertEqual(
            UsageForecastPresentation(forecast: forecast(state: .noExhaustion), now: now).headline,
            "Pode acelerar · sem esgotamento previsto neste ritmo"
        )
        XCTAssertEqual(
            UsageForecastPresentation(
                forecast: forecast(
                    state: .collecting(observedHours: 1.5, sampleCount: 4),
                    exhaustionInHours: nil,
                    ratePerDay: nil,
                    safeRatePerDay: nil
                ),
                now: now
            ).headline,
            "Coletando ritmo · 1h 30min de histórico"
        )
        XCTAssertEqual(
            UsageForecastPresentation(
                forecast: forecast(
                    state: .unavailable,
                    exhaustionInHours: nil,
                    resetInHours: nil,
                    ratePerDay: nil,
                    safeRatePerDay: nil
                ),
                now: now
            ).headline,
            "Previsão indisponível para esta janela"
        )
    }

    func test_barrasUsamUmaEscalaTemporalEGrampeiamValoresInvalidos() {
        let earlyExhaustion = UsageForecastPresentation(
            forecast: forecast(state: .slowDown, exhaustionInHours: 12, resetInHours: 24),
            now: now
        )
        XCTAssertEqual(earlyExhaustion.paceFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(earlyExhaustion.renewalFraction, 1, accuracy: 0.0001)

        let lateExhaustion = UsageForecastPresentation(
            forecast: forecast(state: .canAccelerate, exhaustionInHours: 36, resetInHours: 24),
            now: now
        )
        XCTAssertEqual(lateExhaustion.paceFraction, 1, accuracy: 0.0001)
        XCTAssertEqual(lateExhaustion.renewalFraction, 2.0 / 3.0, accuracy: 0.0001)

        let pastExhaustion = UsageForecastPresentation(
            forecast: forecast(state: .slowDown, exhaustionInHours: -1, resetInHours: 2),
            now: now
        )
        XCTAssertEqual(pastExhaustion.paceFraction, 0)
        XCTAssertEqual(pastExhaustion.renewalFraction, 1)

        let noExhaustion = UsageForecastPresentation(
            forecast: forecast(state: .noExhaustion, exhaustionInHours: nil, resetInHours: 24),
            now: now
        )
        XCTAssertEqual(noExhaustion.paceFraction, 1)
        XCTAssertEqual(noExhaustion.renewalFraction, 1)
    }

    func test_coletaEIndisponivelNaoInventamDatasOuBarras() throws {
        let collecting = UsageForecastPresentation(
            forecast: forecast(
                state: .collecting(observedHours: 2, sampleCount: 4),
                exhaustionInHours: nil,
                ratePerDay: nil,
                safeRatePerDay: nil
            ),
            now: now
        )
        XCTAssertFalse(collecting.showsTimeline)
        XCTAssertEqual(try XCTUnwrap(collecting.collectionProgress), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertNil(collecting.paceDuration)
        XCTAssertNil(collecting.renewalDuration)

        let unavailable = UsageForecastPresentation(
            forecast: forecast(
                state: .unavailable,
                exhaustionInHours: nil,
                resetInHours: nil,
                ratePerDay: nil,
                safeRatePerDay: nil
            ),
            now: now
        )
        XCTAssertFalse(unavailable.showsTimeline)
        XCTAssertNil(unavailable.collectionProgress)
        XCTAssertNil(unavailable.paceDuration)
        XCTAssertNil(unavailable.renewalDuration)
    }

    func test_duracoesCompactasMantemDiasHorasEMinutos() {
        let normal = UsageForecastPresentation(
            forecast: forecast(state: .slowDown, exhaustionInHours: 51, resetInHours: 87),
            now: now
        )
        XCTAssertEqual(normal.paceDuration, "2d 3h")
        XCTAssertEqual(normal.renewalDuration, "3d 15h")

        let short = UsageForecastPresentation(
            forecast: forecast(state: .slowDown, exhaustionInHours: 0.5, resetInHours: 1),
            now: now
        )
        XCTAssertEqual(short.paceDuration, "30min")
        XCTAssertEqual(short.renewalDuration, "1h")
    }
}

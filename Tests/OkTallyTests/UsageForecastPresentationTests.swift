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

    func test_headlinesLocalizadosExplicamCadaEstadoSemPrometerCerteza() {
        XCTAssertEqual(
            UsageForecastPresentation(
                forecast: forecast(state: .slowDown, gap: 36 * hour), now: now
            ).headline,
            LF("Desacelere · pode acabar %@ antes", "1d 12h")
        )
        XCTAssertEqual(
            UsageForecastPresentation(forecast: forecast(state: .onPace), now: now).headline,
            L("No ritmo certo · chega perto da renovação")
        )
        XCTAssertEqual(
            UsageForecastPresentation(
                forecast: forecast(state: .canAccelerate, gap: -30 * hour), now: now
            ).headline,
            LF("Pode acelerar · chega com %@ de folga", "1d 6h")
        )
        XCTAssertEqual(
            UsageForecastPresentation(forecast: forecast(state: .noExhaustion), now: now).headline,
            L("Pode acelerar · sem esgotamento previsto neste ritmo")
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
            LF("Coletando ritmo · %@ de histórico", "1h 30min")
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
            L("Previsão indisponível para esta janela")
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
        XCTAssertEqual(noExhaustion.paceDuration, L("≥ renovação"))
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

    func test_resumoDeRitmoOrientaCorretamenteCadaEstado() {
        let slowDown = UsageForecastPresentation(
            forecast: forecast(state: .slowDown, ratePerDay: 24, safeRatePerDay: 12.2),
            now: now
        )
        XCTAssertEqual(
            slowDown.rateSummary,
            LF(
                "Ritmo 24h: %@%%/dia · Reduza para no máximo %@%%/dia",
                UsageForecastPresentation.decimal(24),
                UsageForecastPresentation.decimal(12.2)
            )
        )

        let onPace = UsageForecastPresentation(
            forecast: forecast(state: .onPace, ratePerDay: 12.3, safeRatePerDay: 12.2),
            now: now
        )
        XCTAssertEqual(
            onPace.rateSummary,
            LF(
                "Ritmo 24h: %@%%/dia · Meta: %@%%/dia",
                UsageForecastPresentation.decimal(12.3),
                UsageForecastPresentation.decimal(12.2)
            )
        )

        let canAccelerate = UsageForecastPresentation(
            forecast: forecast(state: .canAccelerate, ratePerDay: 8, safeRatePerDay: 12.2),
            now: now
        )
        XCTAssertEqual(
            canAccelerate.rateSummary,
            LF(
                "Ritmo 24h: %@%%/dia · Pode usar até %@%%/dia",
                UsageForecastPresentation.decimal(8),
                UsageForecastPresentation.decimal(12.2)
            )
        )
    }

    func test_metricasDoDetalheDiferenciamFaltaDeColetaSemInventarData() {
        let risk = ForecastDetailMetrics(
            forecast: forecast(
                state: .slowDown,
                exhaustionInHours: 16,
                resetInHours: 24,
                gap: 8 * hour
            )
        ).items
        XCTAssertEqual(risk.first(where: { $0.label == L("Falta projetada") })?.value,
                       UsageForecastPresentation.durationText(8 * hour))
        XCTAssertEqual(risk.first(where: { $0.label == L("Ritmo observado") })?.value,
                       LF("%@%%/dia", UsageForecastPresentation.decimal(14.2)))
        XCTAssertEqual(risk.first(where: { $0.label == L("Reduza para") })?.value,
                       LF("no máximo %@%%/dia", UsageForecastPresentation.decimal(11.8)))

        let headroom = ForecastDetailMetrics(
            forecast: forecast(
                state: .canAccelerate,
                exhaustionInHours: 36,
                resetInHours: 24,
                ratePerDay: 8,
                safeRatePerDay: 12.2,
                gap: -12 * hour
            )
        ).items
        XCTAssertEqual(headroom.first(where: { $0.label == L("Pode usar") })?.value,
                       LF("até %@%%/dia", UsageForecastPresentation.decimal(12.2)))

        let collecting = ForecastDetailMetrics(
            forecast: forecast(
                state: .collecting(observedHours: 2, sampleCount: 4),
                exhaustionInHours: nil,
                resetInHours: 24,
                ratePerDay: nil,
                safeRatePerDay: 11.8,
                gap: nil
            )
        ).items
        XCTAssertEqual(collecting.first(where: { $0.label == L("Esgotamento previsto") })?.value,
                       L("Ainda coletando histórico"))
    }
}

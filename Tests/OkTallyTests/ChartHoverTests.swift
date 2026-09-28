import XCTest
@testable import OkTally

/// A lógica que o hover dos gráficos precisa e que NÃO depende de renderizar nada:
/// encaixe no ponto mais próximo, detalhamento ordenado com porcentagens, posição do
/// tooltip grampeada dentro da área do gráfico, rótulo de intensidade do heatmap e
/// formatação de número/data. Mora fora das views justamente para caber aqui.
final class ChartHoverTests: XCTestCase {
    /// 2026-04-15 12:00 UTC (uma quarta-feira), fixo — nada aqui pode depender do
    /// relógio real.
    private let now = Date(timeIntervalSince1970: 1_776_254_400)

    private func day(_ offset: Int) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -offset, to: now)!
        return TokenAnalytics.dayKey(date)
    }

    // MARK: - Encaixe no ponto mais próximo

    func test_nearestIndex_isNilForEmptySeries() {
        XCTAssertNil(ChartHover.nearestIndex(in: [], to: now))
    }

    func test_nearestIndex_snapsToTheClosestSample() {
        let dates = [
            now.addingTimeInterval(-2 * 86_400),
            now.addingTimeInterval(-86_400),
            now
        ]
        // Um pouco depois do meio entre o segundo e o terceiro ponto: encaixa no terceiro.
        XCTAssertEqual(ChartHover.nearestIndex(in: dates, to: now.addingTimeInterval(-40_000)), 2)
        XCTAssertEqual(ChartHover.nearestIndex(in: dates, to: now.addingTimeInterval(-50_000)), 1)
    }

    func test_nearestIndex_clampsBeyondTheEnds() {
        let dates = [now.addingTimeInterval(-86_400), now]
        XCTAssertEqual(ChartHover.nearestIndex(in: dates, to: now.addingTimeInterval(-10 * 86_400)), 0)
        XCTAssertEqual(ChartHover.nearestIndex(in: dates, to: now.addingTimeInterval(10 * 86_400)), 1)
    }

    func test_nearestIndex_prefersTheEarlierSampleOnATie() {
        // Empate exato tem que ser determinístico, senão o tooltip pisca entre dois dias
        // quando o cursor para no meio.
        let dates = [now.addingTimeInterval(-86_400), now]
        XCTAssertEqual(ChartHover.nearestIndex(in: dates, to: now.addingTimeInterval(-43_200)), 0)
    }

    func test_nearestDay_snapsAStringKeyToTheClosestDay() {
        let days = [day(3), day(2), day(1), day(0)]
        let target = Calendar(identifier: .gregorian)
            .date(byAdding: .hour, value: -2, to: now)!
        XCTAssertEqual(ChartHover.nearestDay(in: days, to: target), day(0))
    }

    func test_nearestDay_isNilWhenNoKeyParses() {
        XCTAssertNil(ChartHover.nearestDay(in: ["não é data"], to: now))
    }

    // MARK: - Detalhamento por provedor

    func test_breakdown_keepsOnlyTheHoveredDay() {
        let points = [
            TrendPoint(day: day(0), providerId: "codex", tokens: 100),
            TrendPoint(day: day(1), providerId: "codex", tokens: 999)
        ]
        let rows = ChartHover.breakdown(points: points, day: day(0))
        XCTAssertEqual(rows.map(\.tokens), [100])
    }

    func test_breakdown_isSortedByTokensDescending() {
        let points = [
            TrendPoint(day: day(0), providerId: "claude", tokens: 50),
            TrendPoint(day: day(0), providerId: "codex", tokens: 300),
            TrendPoint(day: day(0), providerId: "opencode", tokens: 150)
        ]
        let rows = ChartHover.breakdown(points: points, day: day(0))
        XCTAssertEqual(rows.map(\.providerId), ["codex", "opencode", "claude"])
    }

    func test_breakdown_breaksTiesByProviderIdSoTheOrderIsStable() {
        let points = [
            TrendPoint(day: day(0), providerId: "opencode", tokens: 100),
            TrendPoint(day: day(0), providerId: "claude", tokens: 100)
        ]
        let rows = ChartHover.breakdown(points: points, day: day(0))
        XCTAssertEqual(rows.map(\.providerId), ["claude", "opencode"])
    }

    func test_breakdown_fractionIsTheShareOfThatDay() {
        let points = [
            TrendPoint(day: day(0), providerId: "codex", tokens: 300),
            TrendPoint(day: day(0), providerId: "claude", tokens: 100)
        ]
        let rows = ChartHover.breakdown(points: points, day: day(0))
        XCTAssertEqual(rows[0].fraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(rows[1].fraction, 0.25, accuracy: 0.0001)
    }

    func test_breakdown_fractionIsZeroWhenTheDayIsEmpty() {
        // Divisão por zero em Swift devolve NaN, e `max(0, min(1, .nan))` é 1.0: uma linha
        // com 0 token apareceria como 100%.
        let points = [TrendPoint(day: day(0), providerId: "codex", tokens: 0)]
        let rows = ChartHover.breakdown(points: points, day: day(0))
        XCTAssertEqual(rows.first?.fraction, 0)
    }

    func test_breakdownTotal_sumsTheHoveredDay() {
        let points = [
            TrendPoint(day: day(0), providerId: "codex", tokens: 300),
            TrendPoint(day: day(0), providerId: "claude", tokens: 100),
            TrendPoint(day: day(1), providerId: "codex", tokens: 999)
        ]
        XCTAssertEqual(ChartHover.total(points: points, day: day(0)), 400)
    }

    // MARK: - Fatia do donut

    func test_sliceIndex_mapsTheCumulativeAngleValueToASlice() {
        let values = [300, 200, 100]
        XCTAssertEqual(ChartHover.sliceIndex(forAngleValue: 1, in: values), 0)
        XCTAssertEqual(ChartHover.sliceIndex(forAngleValue: 300, in: values), 0)
        XCTAssertEqual(ChartHover.sliceIndex(forAngleValue: 301, in: values), 1)
        XCTAssertEqual(ChartHover.sliceIndex(forAngleValue: 500, in: values), 1)
        XCTAssertEqual(ChartHover.sliceIndex(forAngleValue: 501, in: values), 2)
        XCTAssertEqual(ChartHover.sliceIndex(forAngleValue: 600, in: values), 2)
    }

    func test_sliceIndex_isNilOutsideTheDomain() {
        XCTAssertNil(ChartHover.sliceIndex(forAngleValue: 601, in: [300, 200, 100]))
        XCTAssertNil(ChartHover.sliceIndex(forAngleValue: -1, in: [300, 200, 100]))
        XCTAssertNil(ChartHover.sliceIndex(forAngleValue: 10, in: []))
    }

    func test_sliceIndex_skipsSlicesWithoutAngle() {
        // Um provider com zero token não ocupa ângulo nenhum: nunca pode ser o selecionado.
        XCTAssertEqual(ChartHover.sliceIndex(forAngleValue: 100, in: [100, 0, 50]), 0)
        XCTAssertEqual(ChartHover.sliceIndex(forAngleValue: 101, in: [100, 0, 50]), 2)
    }

    // MARK: - Posição do tooltip

    private let plot = CGRect(x: 0, y: 0, width: 400, height: 200)
    private let tip = CGSize(width: 140, height: 60)

    func test_tooltipOrigin_sitsBesideTheCursorWhenThereIsRoom() {
        let origin = ChartHover.tooltipOrigin(
            anchor: CGPoint(x: 100, y: 100), tooltipSize: tip, bounds: plot, gap: 12)
        XCTAssertEqual(origin.x, 112, accuracy: 0.001)
        // Centralizado na vertical em relação ao cursor.
        XCTAssertEqual(origin.y, 70, accuracy: 0.001)
    }

    func test_tooltipOrigin_flipsToTheOtherSideNearTheRightEdge() {
        let origin = ChartHover.tooltipOrigin(
            anchor: CGPoint(x: 380, y: 100), tooltipSize: tip, bounds: plot, gap: 12)
        XCTAssertEqual(origin.x, 380 - 12 - 140, accuracy: 0.001)
    }

    func test_tooltipOrigin_neverLeavesThePlotHorizontally() {
        // Cursor encostado na esquerda com um tooltip largo: não cabe de nenhum lado, e o
        // certo é grampear dentro do gráfico em vez de vazar e ser cortado.
        let origin = ChartHover.tooltipOrigin(
            anchor: CGPoint(x: 6, y: 100),
            tooltipSize: CGSize(width: 396, height: 60),
            bounds: plot,
            gap: 12
        )
        XCTAssertGreaterThanOrEqual(origin.x, plot.minX)
        XCTAssertLessThanOrEqual(origin.x + 396, plot.maxX)
    }

    func test_tooltipOrigin_clampsVerticallyAtBothEnds() {
        let top = ChartHover.tooltipOrigin(
            anchor: CGPoint(x: 100, y: 4), tooltipSize: tip, bounds: plot, gap: 12)
        XCTAssertEqual(top.y, plot.minY, accuracy: 0.001)

        let bottom = ChartHover.tooltipOrigin(
            anchor: CGPoint(x: 100, y: 196), tooltipSize: tip, bounds: plot, gap: 12)
        XCTAssertEqual(bottom.y, plot.maxY - tip.height, accuracy: 0.001)
    }

    func test_tooltipOrigin_respectsANonZeroPlotOrigin() {
        let shifted = CGRect(x: 30, y: 10, width: 400, height: 200)
        let origin = ChartHover.tooltipOrigin(
            anchor: CGPoint(x: 40, y: 15), tooltipSize: tip, bounds: shifted, gap: 12)
        XCTAssertGreaterThanOrEqual(origin.x, shifted.minX)
        XCTAssertEqual(origin.y, shifted.minY, accuracy: 0.001)
    }

    func test_tooltipOrigin_doesNotOverflowAPlotSmallerThanTheTooltip() {
        // Sparkline de 70×18: o tooltip é maior que a área. Grampear no canto é a única
        // saída honesta — vazar seria ser cortado pelo card.
        let tiny = CGRect(x: 0, y: 0, width: 70, height: 18)
        let origin = ChartHover.tooltipOrigin(
            anchor: CGPoint(x: 35, y: 9), tooltipSize: tip, bounds: tiny, gap: 8)
        XCTAssertEqual(origin.x, tiny.minX, accuracy: 0.001)
        XCTAssertEqual(origin.y, tiny.minY, accuracy: 0.001)
    }

    // MARK: - Intensidade do heatmap

    func test_quartiles_areNilWithoutActiveDays() {
        XCTAssertNil(ChartHover.quartiles([]))
    }

    func test_quartileLevel_agreesWithHeatLevels() {
        // As duas leituras da MESMA distribuição: a cor da célula e o texto do tooltip não
        // podem discordar ("célula mais forte" + "quartil menos ativo").
        let tokens = [10, 20, 30, 40, 50, 60, 70, 80, 900]
        let analytics = TokenAnalytics(dailyBuckets: tokens.enumerated().map { index, value in
            DailyTokens(day: day(index), tokens: value)
        })
        let levels = analytics.heatLevels()
        let quartiles = try! XCTUnwrap(ChartHover.quartiles(tokens.sorted()))
        for (index, value) in tokens.enumerated() {
            XCTAssertEqual(
                ChartHover.quartileLevel(tokens: value, quartiles: quartiles),
                levels[day(index)],
                "divergência no dia de \(value) tokens"
            )
        }
    }

    func test_intensityLabel_describesTheTopQuartileAsSuch() {
        XCTAssertEqual(ChartHover.intensityLabel(level: 4), L("top 25% dos dias"))
        XCTAssertEqual(ChartHover.intensityLabel(level: 3), L("acima da mediana"))
        XCTAssertEqual(ChartHover.intensityLabel(level: 2), L("abaixo da mediana"))
        XCTAssertEqual(ChartHover.intensityLabel(level: 1), L("25% menos ativos"))
    }

    func test_intensityLabel_isNilForADayWithoutUse() {
        XCTAssertNil(ChartHover.intensityLabel(level: 0))
    }

    // MARK: - Formatação

    func test_groupedTokens_usesTheLocaleSeparator() {
        XCTAssertEqual(ChartHover.groupedTokens(1_234_567, locale: Locale(identifier: "pt_BR")), "1.234.567")
        XCTAssertEqual(ChartHover.groupedTokens(1_234_567, locale: Locale(identifier: "en_US")), "1,234,567")
    }

    func test_groupedTokens_leavesSmallNumbersAlone() {
        XCTAssertEqual(ChartHover.groupedTokens(42, locale: Locale(identifier: "pt_BR")), "42")
    }

    func test_exactTokens_pairsTheGroupedNumberWithTheCompactOne() {
        // O tooltip precisa dos dois: o compacto é o que o olho lê, o exato é o que o dono
        // confere.
        let label = ChartHover.exactTokens(1_234_567, locale: Locale(identifier: "pt_BR"))
        XCTAssertTrue(label.contains("1.234.567"), label)
        XCTAssertTrue(label.contains(TokenAnalytics.compactTokens(1_234_567)), label)
    }

    func test_exactTokens_doesNotRepeatItselfBelowAThousand() {
        // Abaixo de mil o compacto É o número exato: "800 · 800" é ruído.
        XCTAssertEqual(ChartHover.exactTokens(800, locale: Locale(identifier: "pt_BR")), "800")
    }

    func test_dayLabel_hasWeekdayAndDayNumber() {
        let label = ChartHover.dayLabel(now, locale: Locale(identifier: "pt_BR"))
        XCTAssertTrue(label.contains("15"), label)
        XCTAssertTrue(label.lowercased().contains("qua"), label)
        XCTAssertTrue(label.lowercased().contains("abr"), label)
    }

    func test_dayLabel_startsCapitalized() {
        // O pt_BR abrevia o dia da semana em minúscula; num tooltip isso lê como erro.
        let label = ChartHover.dayLabel(now, locale: Locale(identifier: "pt_BR"))
        XCTAssertEqual(label.first, label.first?.uppercased().first)
    }

    func test_percentLabel_roundsToWholePercent() {
        XCTAssertEqual(ChartHover.percentLabel(0.256), "26%")
        XCTAssertEqual(ChartHover.percentLabel(1), "100%")
    }

    func test_percentLabel_treatsNonFiniteFractionsAsZero() {
        XCTAssertEqual(ChartHover.percentLabel(.nan), "0%")
        XCTAssertEqual(ChartHover.percentLabel(2), "100%")
    }
}

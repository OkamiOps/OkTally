# OkTally — Redesign do dashboard: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesenhar as quatro telas do OkTally (Análise, Visão geral, popover e Preferências) sobre uma fundação visual compartilhada, trocando os gráficos desenhados à mão por Swift Charts.

**Architecture:** Uma camada nova `UI/DesignSystem/` concentra tokens e componentes hoje copiados em seis lugares; `UI/Charts/` traz três gráficos em Swift Charts; a lógica de série temporal e de layout do heatmap sai das views para tipos puros testáveis em `Core/`. As telas passam a compor esses blocos em vez de montar layout próprio.

**Tech Stack:** Swift 6.3, SwiftUI, Swift Charts, XCTest, SwiftPM (sem dependência nova — Charts é framework do sistema).

## Global Constraints

- **Deployment target: macOS 26 (Tahoe).** `Package.swift` usa `platforms: [.macOS(.v26)]` e `Resources/Info.plist` usa `LSMinimumSystemVersion` = `26.0`. Nenhum `if #available` para APIs ≤ 26.
- **Nenhuma dependência nova.** A única dependência do pacote continua sendo GRDB.
- **Todo texto visível ao usuário passa por `L(_:)` ou `LF(_:_:)`** (`Sources/OkTally/Core/Localization.swift`). Nunca literal cru numa `Text`.
- **Não há série diária de custo.** `AppModel.estimatedCostByProvider` é um total de 30 dias por provider. Volume diário é sempre em tokens; dinheiro nunca vira série temporal.
- **`SparklineView` plota percentual de cota** (`UsageHistoryPoint.usedPercent`); os gráficos novos plotam tokens por dia. Não fundir as duas séries.
- **Liquid Glass só em cromo** (headers, barra de ações, faixa flutuante). Nunca atrás de número ou de gráfico.
- **Cores de provider vêm de `ProviderPalette.color(for:)`**, nunca hex novo.
- Comentários e mensagens de commit em português, seguindo o repositório.

---

## Estrutura de arquivos

**Criar:**
- `Sources/OkTally/UI/DesignSystem/Theme.swift` — tokens (espaçamento, raio, tipografia, superfícies, vidro).
- `Sources/OkTally/UI/DesignSystem/Components.swift` — `DashboardCard`, `StatTile`, `SectionHeader`, `DeltaBadge`, `ShareBar`, `ProgressRing`.
- `Sources/OkTally/UI/DesignSystem/ProviderSidebarRow.swift` — linha de sidebar compartilhada.
- `Sources/OkTally/Core/TrendSeries.swift` — tipos puros da série temporal.
- `Sources/OkTally/Core/HeatmapLayout.swift` — matemática do heatmap responsivo.
- `Sources/OkTally/Core/FieldCommit.swift` — regras de auto-save.
- `Sources/OkTally/UI/Charts/DailyTokensAreaChart.swift`
- `Sources/OkTally/UI/Charts/StackedProviderBarChart.swift`
- `Sources/OkTally/UI/Charts/ProviderShareDonut.swift`
- `Sources/OkTally/UI/AnalyticsDashboardView.swift` — a grade bento nova.
- `Sources/OkTally/UI/ProviderPaneScaffold.swift` — casca dos panes de provider.
- `Tests/OkTallyTests/TrendSeriesTests.swift`
- `Tests/OkTallyTests/HeatmapLayoutTests.swift`
- `Tests/OkTallyTests/FieldCommitTests.swift`

**Modificar:**
- `Package.swift:7` — plataforma.
- `Resources/Info.plist` — `LSMinimumSystemVersion`.
- `Sources/OkTally/UI/AnalyticsSection.swift` — heatmap vira responsivo; os chips saem (migram para o dashboard).
- `Sources/OkTally/UI/MainWindowView.swift` — Visão geral e detalhe sobre os componentes novos.
- `Sources/OkTally/UI/PopoverView.swift` — tokens + faixa "hoje".
- `Sources/OkTally/UI/PreferencesView.swift` — `Form` agrupado, auto-save, scaffold.
- `Sources/OkTally/Preferences/PreferencesStore.swift` — nada estrutural; só usado pelos testes de auto-save.
- `Tests/OkTallyTests/ReadmeAssetRenderer.swift` — renderiza as telas novas.
- `README.md`, `README.pt-BR.md`, `README.de.md`, `README.fr.md`, `CHANGELOG.md` — requisito de sistema.

---

## Fase 0 — Plataforma

### Task 1: Subir o deployment target para macOS 26

**Files:**
- Modify: `Package.swift:7`
- Modify: `Resources/Info.plist`
- Modify: `README.md`, `README.pt-BR.md`, `README.de.md`, `README.fr.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: nada.
- Produces: toda task seguinte pode usar API de macOS 26 sem `if #available`.

- [ ] **Step 1: Trocar a plataforma no Package.swift**

Em `Package.swift`, linha 7:

```swift
    platforms: [.macOS(.v26)],
```

- [ ] **Step 2: Trocar o mínimo no Info.plist**

Em `Resources/Info.plist`, o valor de `LSMinimumSystemVersion` passa de `13.0` para:

```xml
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
```

- [ ] **Step 3: Compilar para confirmar que o toolchain aceita**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` — sem erro de plataforma. Se aparecer `the library 'OkTally' requires macos 26.0`, algum alvo do `Package.swift` ficou para trás; corrija e repita.

- [ ] **Step 4: Rodar a suíte inteira para garantir que nada quebrou**

Run: `swift test 2>&1 | tail -15`
Expected: todos os testes passam. Esta é a linha de base — se algo já falhava antes desta task, anote e não tente consertar aqui.

- [ ] **Step 5: Atualizar o requisito declarado nos quatro READMEs**

Procure a linha de requisito em cada arquivo:

Run: `grep -n "macOS 13\|macOS 13.0\|Requirements\|Requisitos\|Voraussetzungen\|Prérequis" README.md README.pt-BR.md README.de.md README.fr.md`

Troque a versão citada por macOS 26 (Tahoe) em cada um, no idioma do arquivo. Se algum README não citar requisito de sistema, adicione uma linha na seção de instalação — em inglês: `Requires macOS 26 (Tahoe) or later.`

- [ ] **Step 6: Registrar a quebra de compatibilidade no CHANGELOG**

No topo de `CHANGELOG.md`, dentro da seção não lançada (crie `## [Unreleased]` se não existir):

```markdown
### Alterado
- **Requisito de sistema agora é macOS 26 (Tahoe).** Versões anteriores do macOS não
  recebem mais atualizações — a mudança libera Liquid Glass e as APIs novas de Swift
  Charts usadas no redesign da interface.
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift Resources/Info.plist README.md README.pt-BR.md README.de.md README.fr.md CHANGELOG.md
git commit -m "build: sobe o deployment target para macOS 26"
```

---

## Fase 1 — Lógica pura (TDD)

### Task 2: TrendSeries — séries e deltas do dashboard

**Files:**
- Create: `Sources/OkTally/Core/TrendSeries.swift`
- Test: `Tests/OkTallyTests/TrendSeriesTests.swift`

**Interfaces:**
- Consumes: `TokenAnalytics` e `DailyTokens` de `Sources/OkTally/Core/TokenAnalytics.swift`.
- Produces:
  - `enum TrendWindow: Int, CaseIterable { case days30 = 30, days90 = 90, days365 = 365 }` com `var label: String`.
  - `struct TrendPoint: Equatable { let day: String; let providerId: String; let tokens: Int }`
  - `enum TrendSeries` com:
    - `static func points(byProvider: [String: TokenAnalytics], window: TrendWindow, now: Date) -> [TrendPoint]`
    - `static func dailyTotals(_ analytics: TokenAnalytics, lastDays: Int, now: Date) -> [DailyTokens]`
    - `static func delta(current: Int, previous: Int) -> Double?`
    - `static func share(byProvider: [String: TokenAnalytics], lastDays: Int, now: Date) -> [(providerId: String, tokens: Int)]`

- [ ] **Step 1: Escrever os testes que falham**

Crie `Tests/OkTallyTests/TrendSeriesTests.swift`:

```swift
import XCTest
@testable import OkTally

final class TrendSeriesTests: XCTestCase {
    /// 2026-08-15 12:00 UTC, fixo — nada aqui pode depender do relógio real.
    private let now = Date(timeIntervalSince1970: 1_776_254_400)

    private func day(_ offset: Int) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -offset, to: now)!
        return TokenAnalytics.dayKey(date)
    }

    private func analytics(_ pairs: [(Int, Int)]) -> TokenAnalytics {
        TokenAnalytics(dailyBuckets: pairs.map { DailyTokens(day: day($0.0), tokens: $0.1) })
    }

    func test_points_keepsOnlyDaysInsideTheWindow() {
        let source = ["codex": analytics([(0, 100), (29, 200), (45, 999)])]
        let points = TrendSeries.points(byProvider: source, window: .days30, now: now)
        XCTAssertEqual(points.count, 2)
        XCTAssertFalse(points.contains { $0.day == day(45) })
    }

    func test_points_tagsEachPointWithItsProvider() {
        let source = [
            "codex": analytics([(1, 10)]),
            "claude": analytics([(1, 20)]),
        ]
        let points = TrendSeries.points(byProvider: source, window: .days30, now: now)
        XCTAssertEqual(Set(points.map(\.providerId)), ["codex", "claude"])
        XCTAssertEqual(points.first { $0.providerId == "claude" }?.tokens, 20)
    }

    func test_points_areSortedByDayAscending() {
        let source = ["codex": analytics([(3, 30), (1, 10), (2, 20)])]
        let days = TrendSeries.points(byProvider: source, window: .days30, now: now).map(\.day)
        XCTAssertEqual(days, days.sorted())
    }

    func test_dailyTotals_fillsMissingDaysWithZero() {
        // Sem o preenchimento o gráfico de área "pula" o dia sem uso e mente sobre o ritmo.
        let totals = TrendSeries.dailyTotals(analytics([(0, 50), (2, 70)]), lastDays: 3, now: now)
        XCTAssertEqual(totals.count, 3)
        XCTAssertEqual(totals.map(\.tokens), [70, 0, 50])
    }

    func test_delta_returnsSignedFraction() {
        XCTAssertEqual(TrendSeries.delta(current: 150, previous: 100), 0.5)
        XCTAssertEqual(TrendSeries.delta(current: 50, previous: 100), -0.5)
    }

    func test_delta_isNilWhenPreviousIsZero() {
        // Crescer a partir de zero não é "+∞ %" — é ausência de comparação.
        XCTAssertNil(TrendSeries.delta(current: 10, previous: 0))
    }

    func test_share_sumsTokensPerProviderDescending() {
        let source = [
            "codex": analytics([(0, 300), (1, 100)]),
            "claude": analytics([(0, 50)]),
        ]
        let share = TrendSeries.share(byProvider: source, lastDays: 30, now: now)
        XCTAssertEqual(share.map(\.providerId), ["codex", "claude"])
        XCTAssertEqual(share.first?.tokens, 400)
    }

    func test_share_omitsProvidersWithoutTokens() {
        let source = ["codex": analytics([(0, 10)]), "mimo": analytics([])]
        let share = TrendSeries.share(byProvider: source, lastDays: 30, now: now)
        XCTAssertEqual(share.map(\.providerId), ["codex"])
    }
}
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `swift test --filter TrendSeriesTests 2>&1 | tail -20`
Expected: FALHA na compilação com `cannot find 'TrendSeries' in scope`.

- [ ] **Step 3: Implementar**

Crie `Sources/OkTally/Core/TrendSeries.swift`:

```swift
// Sources/OkTally/Core/TrendSeries.swift
import Foundation

/// Janelas oferecidas pelo seletor da aba Análise.
enum TrendWindow: Int, CaseIterable {
    case days30 = 30
    case days90 = 90
    case days365 = 365

    var label: String {
        switch self {
        case .days30: return L("30 d")
        case .days90: return L("90 d")
        case .days365: return L("12 m")
        }
    }
}

/// Um ponto do gráfico empilhado: um dia, de um provider.
struct TrendPoint: Equatable {
    let day: String
    let providerId: String
    let tokens: Int
}

/// Transformações puras entre `TokenAnalytics` e o que os gráficos consomem. Fora das
/// views para poder ser testado sem renderizar nada.
enum TrendSeries {
    /// Pontos por provider dentro da janela, ordenados por dia. Dias sem uso de um
    /// provider simplesmente não geram ponto — o gráfico empilhado soma o que existe.
    static func points(byProvider: [String: TokenAnalytics], window: TrendWindow, now: Date = Date()) -> [TrendPoint] {
        let cutoff = dayKeys(lastDays: window.rawValue, now: now)
        let allowed = Set(cutoff)
        var points: [TrendPoint] = []
        for (providerId, analytics) in byProvider {
            for bucket in analytics.dailyBuckets where allowed.contains(bucket.day) && bucket.tokens > 0 {
                points.append(TrendPoint(day: bucket.day, providerId: providerId, tokens: bucket.tokens))
            }
        }
        return points.sorted { ($0.day, $0.providerId) < ($1.day, $1.providerId) }
    }

    /// Série densa dos últimos `lastDays` dias, do mais recente para o mais antigo,
    /// com zero nos dias sem uso — um gráfico de área com buracos mente sobre o ritmo.
    static func dailyTotals(_ analytics: TokenAnalytics, lastDays: Int, now: Date = Date()) -> [DailyTokens] {
        let byDay = Dictionary(uniqueKeysWithValues: analytics.dailyBuckets.map { ($0.day, $0.tokens) })
        return dayKeys(lastDays: lastDays, now: now).map { DailyTokens(day: $0, tokens: byDay[$0] ?? 0) }
    }

    /// Variação relativa. `nil` quando não há base de comparação: crescer a partir de
    /// zero não é uma porcentagem.
    static func delta(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return (Double(current) - Double(previous)) / Double(previous)
    }

    /// Total por provider na janela, do maior para o menor, sem os zerados.
    static func share(byProvider: [String: TokenAnalytics], lastDays: Int, now: Date = Date()) -> [(providerId: String, tokens: Int)] {
        let allowed = Set(dayKeys(lastDays: lastDays, now: now))
        return byProvider
            .map { entry in
                (providerId: entry.key,
                 tokens: entry.value.dailyBuckets.filter { allowed.contains($0.day) }.reduce(0) { $0 + $1.tokens })
            }
            .filter { $0.tokens > 0 }
            .sorted { ($0.tokens, $1.providerId) > ($1.tokens, $0.providerId) }
    }

    /// Chaves "yyyy-MM-dd" do mais recente para o mais antigo.
    private static func dayKeys(lastDays: Int, now: Date) -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        return (0..<max(0, lastDays)).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map(TokenAnalytics.dayKey)
        }
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passa**

Run: `swift test --filter TrendSeriesTests 2>&1 | tail -10`
Expected: todos os testes de `TrendSeriesTests` passam.

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/Core/TrendSeries.swift Tests/OkTallyTests/TrendSeriesTests.swift
git commit -m "feat(core): TrendSeries — séries, deltas e share do dashboard"
```

---

### Task 3: HeatmapLayout — o cálculo que acaba com o espaço morto

**Files:**
- Create: `Sources/OkTally/Core/HeatmapLayout.swift`
- Test: `Tests/OkTallyTests/HeatmapLayoutTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `enum HeatmapLayout` com `static func metrics(availableWidth: CGFloat, gap: CGFloat, minCell: CGFloat, maxCell: CGFloat, maxWeeks: Int) -> HeatmapMetrics` e `struct HeatmapMetrics: Equatable { let cell: CGFloat; let weeks: Int }`.

- [ ] **Step 1: Escrever os testes que falham**

Crie `Tests/OkTallyTests/HeatmapLayoutTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import OkTally

final class HeatmapLayoutTests: XCTestCase {
    private func metrics(_ width: CGFloat, maxWeeks: Int = 53) -> HeatmapMetrics {
        HeatmapLayout.metrics(availableWidth: width, gap: 2, minCell: 8, maxCell: 16, maxWeeks: maxWeeks)
    }

    func test_fillsTheAvailableWidth() {
        // O bug original: célula fixa de 10 pt deixava metade do card vazia.
        let m = metrics(600)
        let used = CGFloat(m.weeks) * m.cell + CGFloat(m.weeks - 1) * 2
        XCTAssertEqual(used, 600, accuracy: m.cell)
    }

    func test_cellNeverExceedsMax() {
        XCTAssertLessThanOrEqual(metrics(2000).cell, 16)
    }

    func test_cellNeverGoesBelowMin() {
        XCTAssertGreaterThanOrEqual(metrics(120).cell, 8)
    }

    func test_narrowWidthDropsWeeksInsteadOfShrinkingPastMin() {
        let narrow = metrics(120)
        let wide = metrics(600)
        XCTAssertLessThan(narrow.weeks, wide.weeks)
    }

    func test_neverExceedsMaxWeeks() {
        XCTAssertLessThanOrEqual(metrics(4000, maxWeeks: 53).weeks, 53)
    }

    func test_alwaysYieldsAtLeastOneWeek() {
        XCTAssertGreaterThanOrEqual(metrics(0).weeks, 1)
        XCTAssertGreaterThanOrEqual(metrics(-50).weeks, 1)
    }
}
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `swift test --filter HeatmapLayoutTests 2>&1 | tail -20`
Expected: FALHA com `cannot find 'HeatmapLayout' in scope`.

- [ ] **Step 3: Implementar**

Crie `Sources/OkTally/Core/HeatmapLayout.swift`:

```swift
// Sources/OkTally/Core/HeatmapLayout.swift
import CoreGraphics

/// Célula e número de semanas que preenchem a largura disponível.
struct HeatmapMetrics: Equatable {
    let cell: CGFloat
    let weeks: Int
}

/// O heatmap antigo tinha célula fixa de 10 pt e 26 semanas: numa janela larga sobrava
/// metade do card vazia. Aqui a largura manda — primeiro tenta caber o máximo de semanas
/// com célula legível, depois ajusta a célula para consumir o resto.
enum HeatmapLayout {
    static func metrics(
        availableWidth: CGFloat,
        gap: CGFloat = 2,
        minCell: CGFloat = 8,
        maxCell: CGFloat = 16,
        maxWeeks: Int = 53
    ) -> HeatmapMetrics {
        let width = max(0, availableWidth)
        // Quantas colunas cabem com a célula no menor tamanho legível.
        let widest = Int(((width + gap) / (minCell + gap)).rounded(.down))
        let weeks = max(1, min(maxWeeks, widest))
        // Com o número de colunas fixo, a célula cresce para consumir a sobra.
        let raw = (width - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
        let cell = min(maxCell, max(minCell, raw))
        return HeatmapMetrics(cell: cell, weeks: weeks)
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passa**

Run: `swift test --filter HeatmapLayoutTests 2>&1 | tail -10`
Expected: todos passam. Se `test_fillsTheAvailableWidth` falhar por folga maior que uma célula, o arredondamento de `widest` está cortando uma coluna — revise o `.rounded(.down)`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/Core/HeatmapLayout.swift Tests/OkTallyTests/HeatmapLayoutTests.swift
git commit -m "feat(core): HeatmapLayout — heatmap que preenche a largura"
```

---

### Task 4: FieldCommit — as regras do auto-save

**Files:**
- Create: `Sources/OkTally/Core/FieldCommit.swift`
- Test: `Tests/OkTallyTests/FieldCommitTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `enum FieldCommit` com `static func sanitized(_ raw: String, previous: String) -> String?` e `static func lowBalance(_ raw: String) -> Double?`.

- [ ] **Step 1: Escrever os testes que falham**

Crie `Tests/OkTallyTests/FieldCommitTests.swift`:

```swift
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
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `swift test --filter FieldCommitTests 2>&1 | tail -20`
Expected: FALHA com `cannot find 'FieldCommit' in scope`.

- [ ] **Step 3: Implementar**

Crie `Sources/OkTally/Core/FieldCommit.swift`:

```swift
// Sources/OkTally/Core/FieldCommit.swift
import Foundation

/// Regras do auto-save das Preferências. Os campos passaram a gravar sozinhos (no Enter
/// e ao perder o foco), então precisam de guardas que o botão "Salvar" antes dava de
/// graça: campo vazio nunca apaga credencial, e valor inalterado não gera escrita.
enum FieldCommit {
    /// Valor a persistir, ou `nil` quando a edição deve ser ignorada.
    static func sanitized(_ raw: String, previous: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != previous.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return trimmed
    }

    /// Saldo em USD, aceitando vírgula decimal. `nil` para valores não positivos ou lixo.
    static func lowBalance(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }
}
```

- [ ] **Step 4: Rodar e confirmar que passa**

Run: `swift test --filter FieldCommitTests 2>&1 | tail -10`
Expected: todos passam.

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/Core/FieldCommit.swift Tests/OkTallyTests/FieldCommitTests.swift
git commit -m "feat(core): FieldCommit — regras do auto-save das Preferências"
```

---

## Fase 2 — Fundação visual

### Task 5: Theme e componentes compartilhados

**Files:**
- Create: `Sources/OkTally/UI/DesignSystem/Theme.swift`
- Create: `Sources/OkTally/UI/DesignSystem/Components.swift`

**Interfaces:**
- Consumes: `ProviderPalette` (`Sources/OkTally/UI/ProviderPalette.swift`).
- Produces:
  - `enum Theme` com `enum Space { static let xs/sm/md/lg/xl: CGFloat }`, `enum Radius { static let small/medium/large: CGFloat }`, `enum Font` (`metricHero`, `metricLarge`, `metricMedium`, `body`, `label` — todos `SwiftUI.Font`), `static func surface() -> Color`, `static func surfaceRaised() -> Color`, `static func surfaceAccent(_ color: Color) -> LinearGradient`.
  - `struct DashboardCard<Content: View>: View` — `init(padding: CGFloat = Theme.Space.lg, @ViewBuilder content: () -> Content)`.
  - `struct StatTile: View` — `init(title: String, value: String, caption: String?, tint: Color, emphasis: StatTile.Emphasis)` com `enum Emphasis { case regular, hero }`.
  - `struct SectionHeader: View` — `init(_ text: String)`.
  - `struct DeltaBadge: View` — `init(fraction: Double?)`.
  - `struct ShareBar: View` — `init(fraction: Double, color: Color)`.
  - `struct ProgressRing: View` — `init(fraction: Double, color: Color, lineWidth: CGFloat = 6, size: CGFloat = 44)`.
  - `extension View { func glassChrome() -> some View }`.

- [ ] **Step 1: Criar os tokens**

Crie `Sources/OkTally/UI/DesignSystem/Theme.swift`:

```swift
// Sources/OkTally/UI/DesignSystem/Theme.swift
import SwiftUI

/// Tokens visuais do app. Antes disto, `RoundedRectangle(cornerRadius: 12)
/// .fill(Color.primary.opacity(0.045))` estava copiado em seis lugares — mudar a
/// estética exigia editar todos.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum Font {
        static let metricHero = SwiftUI.Font.system(size: 34, weight: .bold, design: .rounded)
        static let metricLarge = SwiftUI.Font.system(size: 22, weight: .bold, design: .rounded)
        static let metricMedium = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let body = SwiftUI.Font.system(size: 12)
        static let label = SwiftUI.Font.system(size: 9, weight: .semibold)
    }

    /// Superfícies derivadas de `Color.primary` para acompanhar claro e escuro sozinhas.
    static func surface() -> Color { Color.primary.opacity(0.045) }
    static func surfaceRaised() -> Color { Color.primary.opacity(0.075) }
    static func border() -> Color { Color.primary.opacity(0.07) }

    /// Fundo tingido do bloco-herói.
    static func surfaceAccent(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.18), color.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// Liquid Glass, restrito a cromo (headers, barras de ação). Vidro atrás de número ou
    /// gráfico prejudica a leitura, então nada de conteúdo denso usa isto.
    func glassChrome() -> some View {
        self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}
```

Nota para quem implementa: `glassChrome` começa com `.regularMaterial`, que compila em qualquer SDK. Na Task 13 há um passo dedicado a trocar por `.glassEffect` depois de confirmar a assinatura exata da API no SDK 26.5 — não tente adivinhar a API agora.

- [ ] **Step 2: Criar os componentes**

Crie `Sources/OkTally/UI/DesignSystem/Components.swift`:

```swift
// Sources/OkTally/UI/DesignSystem/Components.swift
import SwiftUI

/// Card padrão: substitui as seis cópias do mesmo fundo+borda.
struct DashboardCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.surface()))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.border()))
    }
}

/// Métrica com hierarquia: `.hero` é o bloco tingido e grande, `.regular` orbita.
struct StatTile: View {
    enum Emphasis { case regular, hero }

    let title: String
    let value: String
    var caption: String?
    var tint: Color = .accentColor
    var emphasis: Emphasis = .regular

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title)
            Text(value)
                .font(emphasis == .hero ? Theme.Font.metricHero : Theme.Font.metricLarge)
                .monospacedDigit()
                .foregroundStyle(emphasis == .hero ? tint : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            switch emphasis {
            case .hero: shape.fill(Theme.surfaceAccent(tint))
            case .regular: shape.fill(Theme.surface())
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.border()))
    }
}

/// O rótulo maiúsculo com tracking, hoje repetido em quatro telas.
struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.label)
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}

/// Variação percentual. `nil` (sem base de comparação) some em vez de mostrar "+∞".
struct DeltaBadge: View {
    let fraction: Double?

    var body: some View {
        if let fraction {
            let up = fraction >= 0
            let tint: Color = abs(fraction) < 0.005 ? .secondary : (up ? .green : .red)
            Label(
                String(format: "%@%.0f%%", up ? "+" : "−", abs(fraction) * 100),
                systemImage: up ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
        }
    }
}

/// Fatia de participação de um provider.
struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(3, geo.size.width * max(0, min(1, fraction))))
            }
        }
        .frame(height: 6)
    }
}

/// Anel reaproveitável (streak, cota).
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 6
    var size: CGFloat = 44
    var label: String?

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: fraction)
            if let label {
                Text(label)
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}
```

- [ ] **Step 3: Compilar**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`. Erro provável: colisão de nome se `Theme` já existir — confirme com `grep -rn "enum Theme\|struct Theme" Sources` antes de renomear qualquer coisa.

- [ ] **Step 4: Rodar a suíte para garantir que nada regrediu**

Run: `swift test 2>&1 | tail -10`
Expected: mesma quantidade de testes passando de antes.

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/UI/DesignSystem
git commit -m "feat(ui): fundação do design system — tokens e componentes"
```

---

### Task 6: Os três gráficos em Swift Charts

**Files:**
- Create: `Sources/OkTally/UI/Charts/DailyTokensAreaChart.swift`
- Create: `Sources/OkTally/UI/Charts/StackedProviderBarChart.swift`
- Create: `Sources/OkTally/UI/Charts/ProviderShareDonut.swift`

**Interfaces:**
- Consumes: `TrendSeries`, `TrendPoint`, `DailyTokens`, `TokenAnalytics.compactTokens(_:)`, `ProviderPalette.color(for:)`.
- Produces:
  - `struct DailyTokensAreaChart: View` — `init(points: [DailyTokens], color: Color, showsAxes: Bool = false)`.
  - `struct StackedProviderBarChart: View` — `init(points: [TrendPoint], providerName: @escaping (String) -> String)`.
  - `struct ProviderShareDonut: View` — `init(share: [(providerId: String, tokens: Int)], providerName: @escaping (String) -> String)`.

- [ ] **Step 1: Criar o gráfico de área**

Crie `Sources/OkTally/UI/Charts/DailyTokensAreaChart.swift`:

```swift
// Sources/OkTally/UI/Charts/DailyTokensAreaChart.swift
import SwiftUI
import Charts

/// Área com gradiente do volume diário. Usada atrás do número-herói e no popover, onde
/// precisa ficar decorativa (`showsAxes: false`) e não competir com o valor.
struct DailyTokensAreaChart: View {
    let points: [DailyTokens]
    let color: Color
    var showsAxes: Bool = false

    var body: some View {
        Chart(points, id: \.day) { point in
            AreaMark(
                x: .value(L("Dia"), TokenAnalytics.date(fromDay: point.day) ?? Date()),
                y: .value(L("Tokens"), point.tokens)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )
            LineMark(
                x: .value(L("Dia"), TokenAnalytics.date(fromDay: point.day) ?? Date()),
                y: .value(L("Tokens"), point.tokens)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(showsAxes ? .automatic : .hidden)
        .chartYAxis(showsAxes ? .automatic : .hidden)
        .chartLegend(.hidden)
    }
}
```

- [ ] **Step 2: Criar o gráfico empilhado**

Crie `Sources/OkTally/UI/Charts/StackedProviderBarChart.swift`:

```swift
// Sources/OkTally/UI/Charts/StackedProviderBarChart.swift
import SwiftUI
import Charts

/// Barras diárias empilhadas por provider: resolve "tendência ao longo do tempo" e
/// "distribuição entre providers" na mesma figura, usando as cores de identidade que já
/// existem em `ProviderPalette`.
struct StackedProviderBarChart: View {
    let points: [TrendPoint]
    let providerName: (String) -> String

    private var providerIds: [String] {
        Array(Set(points.map(\.providerId))).sorted()
    }

    var body: some View {
        Chart(points, id: \.self) { point in
            BarMark(
                x: .value(L("Dia"), TokenAnalytics.date(fromDay: point.day) ?? Date(), unit: .day),
                y: .value(L("Tokens"), point.tokens)
            )
            .foregroundStyle(by: .value(L("Provedor"), point.providerId))
        }
        .chartForegroundStyleScale(
            domain: providerIds,
            range: providerIds.map { ProviderPalette.color(for: $0) }
        )
        .chartLegend(position: .bottom, spacing: Theme.Space.sm)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(TokenAnalytics.compactTokens(tokens))
                    }
                }
            }
        }
    }
}

extension TrendPoint: Hashable {}
```

- [ ] **Step 3: Criar o donut de participação**

Crie `Sources/OkTally/UI/Charts/ProviderShareDonut.swift`:

```swift
// Sources/OkTally/UI/Charts/ProviderShareDonut.swift
import SwiftUI
import Charts

/// Participação de cada provider no período — a leitura instantânea de quem consome o quê.
struct ProviderShareDonut: View {
    let share: [(providerId: String, tokens: Int)]
    let providerName: (String) -> String

    private var total: Int { share.reduce(0) { $0 + $1.tokens } }

    var body: some View {
        Chart(share, id: \.providerId) { slice in
            SectorMark(
                angle: .value(L("Tokens"), slice.tokens),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(ProviderPalette.color(for: slice.providerId))
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 0) {
                Text(TokenAnalytics.compactTokens(total))
                    .font(Theme.Font.metricMedium)
                    .monospacedDigit()
                Text(L("total"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 4: Compilar**

Run: `swift build 2>&1 | tail -15`
Expected: `Build complete!`. Se `SectorMark` não existir na sua SDK, confirme com `grep -rn "SectorMark" $(xcrun --show-sdk-path)/System/Library/Frameworks/Charts.framework 2>/dev/null` — ele existe desde macOS 14, então no alvo 26 deve compilar.

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/UI/Charts
git commit -m "feat(ui): três gráficos em Swift Charts (área, empilhado, donut)"
```

---

## Fase 3 — Telas

### Task 7: Heatmap responsivo

**Files:**
- Modify: `Sources/OkTally/UI/AnalyticsSection.swift` (`TokenHeatmapView`, linhas ~93-190)

**Interfaces:**
- Consumes: `HeatmapLayout.metrics(availableWidth:gap:minCell:maxCell:maxWeeks:)` e `HeatmapMetrics` da Task 3.
- Produces: `TokenHeatmapView` continua com a mesma assinatura pública (`init(analytics:)`), então quem já a usa não muda.

- [ ] **Step 1: Envolver o heatmap num GeometryReader e derivar a métrica**

Em `Sources/OkTally/UI/AnalyticsSection.swift`, `TokenHeatmapView`: remova as constantes `private static let cell: CGFloat = 10` e passe a calcular. O `body` passa a ser:

```swift
    var body: some View {
        GeometryReader { geo in
            let metrics = HeatmapLayout.metrics(availableWidth: geo.size.width)
            let columns = makeColumns(weeks: metrics.weeks)
            VStack(alignment: .leading, spacing: 3) {
                monthLabels(columns, cell: metrics.cell)
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: Self.gap) {
                            ForEach(column) { day in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color(level: day.level))
                                    .frame(width: metrics.cell, height: metrics.cell)
                                    .help(tooltip(day))
                            }
                        }
                    }
                }
                legend
            }
        }
        .frame(height: 132)
    }

    /// Legenda "menos → mais", ausente na versão antiga.
    private var legend: some View {
        HStack(spacing: Theme.Space.xs) {
            Spacer()
            Text(L("menos")).font(.system(size: 8)).foregroundStyle(.tertiary)
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(level: level))
                    .frame(width: 8, height: 8)
            }
            Text(L("mais")).font(.system(size: 8)).foregroundStyle(.tertiary)
        }
    }
```

- [ ] **Step 2: Parametrizar `makeColumns` e `monthLabels` pelo número de semanas e pela célula**

`makeColumns` deixa de usar a propriedade `weeks` e passa a receber o valor:

```swift
    private func makeColumns(weeks: Int) -> [[Day]] {
```

e dentro dela troque `for week in 0..<weeks` mantendo o resto igual, além de trocar o cálculo de `firstCell` para usar o parâmetro:

```swift
        guard let firstCell = calendar.date(byAdding: .day, value: -((weeks - 1) * 7 + weekdayIndex), to: today) else {
            return []
        }
```

`monthLabels` recebe a célula para posicionar os rótulos:

```swift
    private func monthLabels(_ columns: [[Day]], cell: CGFloat) -> some View {
```

e o offset usa o parâmetro:

```swift
                        .offset(x: CGFloat(index) * (cell + Self.gap))
```

Remova também a propriedade `var weeks: Int = 26`, que não é mais a fonte da verdade.

- [ ] **Step 3: Compilar**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`. Se sobrar erro de `weeks` não encontrado, ficou alguma referência à propriedade removida.

- [ ] **Step 4: Verificar visualmente que o espaço morto sumiu**

Run: `RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer 2>&1 | tail -5 && open docs/assets/analytics.png`
Expected: o heatmap agora vai de ponta a ponta do card, com legenda embaixo. Compare com `git stash`/`git stash pop` se quiser o antes e depois.

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/UI/AnalyticsSection.swift
git commit -m "fix(ui): heatmap passa a preencher a largura disponível"
```

---

### Task 8: Aba Análise — a grade bento

**Files:**
- Create: `Sources/OkTally/UI/AnalyticsDashboardView.swift`
- Modify: `Sources/OkTally/UI/MainWindowView.swift` (`AnalyticsScreen`, linhas ~236-300)

**Interfaces:**
- Consumes: `AppModel.aggregatedAnalytics`, `AppModel.analyticsByProvider`, `AppModel.analyticsProviderIds`, `AppModel.estimatedCostByProvider`, `AppModel.snapshotsByProvider`, `AppModel.orderedProviders`; `TrendSeries`, `TrendWindow`; `DailyTokensAreaChart`, `StackedProviderBarChart`, `ProviderShareDonut`; `DashboardCard`, `StatTile`, `SectionHeader`, `DeltaBadge`, `ShareBar`, `ProgressRing`; `TokenHeatmapView`; `QuotaPresentation`.
- Produces: `struct AnalyticsDashboardView: View` — `init(appModel: AppModel)`.

- [ ] **Step 1: Criar a view do dashboard**

Crie `Sources/OkTally/UI/AnalyticsDashboardView.swift`:

```swift
// Sources/OkTally/UI/AnalyticsDashboardView.swift
import SwiftUI

/// A aba Análise redesenhada como grade bento: herói assimétrico, tendência de largura
/// total, recorte por provedor e faixa de cotas. Substitui a pilha de oito chips iguais,
/// que não dizia o que olhar primeiro.
struct AnalyticsDashboardView: View {
    @ObservedObject var appModel: AppModel

    @State private var window: TrendWindow = .days30
    @State private var showsHeatmap = false

    private var byProvider: [String: TokenAnalytics] {
        appModel.analyticsByProvider
    }

    private var aggregated: TokenAnalytics? { appModel.aggregatedAnalytics }

    private func providerName(_ id: String) -> String {
        appModel.orderedProviders.first { $0.id == id }?.displayName ?? id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            if let aggregated {
                heroRow(aggregated)
                trendCard()
                providerRow()
                quotaStrip()
                footnote
            } else if appModel.analyticsProviderIds.isEmpty {
                Text(L("Nenhuma fonte de análise disponível — conecte Codex, Claude Code ou OpenCode."))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Carregando estatísticas de uso…"))
                    .foregroundStyle(.secondary)
            }
        }
        .task { await appModel.loadAllAnalyticsIfStale() }
    }

    // MARK: - Linha 1: herói

    private func heroRow(_ analytics: TokenAnalytics) -> some View {
        let totals = TrendSeries.dailyTotals(analytics, lastDays: 14)
        let today = totals.first?.tokens ?? 0
        let yesterday = totals.dropFirst().first?.tokens ?? 0
        let streak = analytics.effectiveCurrentStreakDays() ?? 0
        let longest = analytics.effectiveLongestStreakDays ?? max(streak, 1)
        return HStack(alignment: .top, spacing: Theme.Space.md) {
            DashboardCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                        SectionHeader(L("Hoje"))
                        DeltaBadge(fraction: TrendSeries.delta(current: today, previous: yesterday))
                        Spacer(minLength: 0)
                    }
                    Text(TokenAnalytics.compactTokens(today))
                        .font(Theme.Font.metricHero)
                        .monospacedDigit()
                    Text(LF("ontem: %@", TokenAnalytics.compactTokens(yesterday)))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    DailyTokensAreaChart(points: totals.reversed(), color: .accentColor)
                        .frame(height: 64)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: Theme.Space.md) {
                DashboardCard(padding: Theme.Space.md) {
                    HStack(spacing: Theme.Space.md) {
                        ProgressRing(
                            fraction: longest > 0 ? Double(streak) / Double(longest) : 0,
                            color: .orange,
                            size: 42,
                            label: "\(streak)"
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            SectionHeader(L("Streak atual"))
                            Text(LF("recorde: %d dias", longest))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                StatTile(
                    title: L("Pico diário"),
                    value: analytics.effectivePeakDailyTokens.map(TokenAnalytics.compactTokens) ?? "—",
                    caption: analytics.longestRunningTurnSeconds.map { LF("tarefa mais longa: %@", TokenAnalytics.durationLabel($0)) }
                )
            }
            .frame(width: 220)
        }
    }

    // MARK: - Linha 2: tendência

    private func trendCard() -> some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    SectionHeader(L("Tendência de uso"))
                    Spacer()
                    Picker("", selection: $window) {
                        ForEach(TrendWindow.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                    Toggle(isOn: $showsHeatmap) {
                        Image(systemName: showsHeatmap ? "square.grid.3x3.fill" : "chart.bar.fill")
                    }
                    .toggleStyle(.button)
                    .help(showsHeatmap ? L("Ver como barras") : L("Ver como heatmap"))
                }
                if showsHeatmap, let aggregated {
                    TokenHeatmapView(analytics: aggregated)
                } else {
                    StackedProviderBarChart(
                        points: TrendSeries.points(byProvider: byProvider, window: window),
                        providerName: providerName
                    )
                    .frame(height: 200)
                }
            }
        }
    }

    // MARK: - Linha 3: por provedor

    private func providerRow() -> some View {
        let share = TrendSeries.share(byProvider: byProvider, lastDays: 30)
        let total = share.reduce(0) { $0 + $1.tokens }
        return HStack(alignment: .top, spacing: Theme.Space.md) {
            DashboardCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    SectionHeader(L("Por provedor"))
                    ForEach(share, id: \.providerId) { entry in
                        providerLine(entry, total: total)
                    }
                }
            }
            DashboardCard {
                VStack(spacing: Theme.Space.sm) {
                    SectionHeader(L("Participação"))
                    ProviderShareDonut(share: share, providerName: providerName)
                        .frame(height: 150)
                }
            }
            .frame(width: 210)
        }
    }

    private func providerLine(_ entry: (providerId: String, tokens: Int), total: Int) -> some View {
        let color = ProviderPalette.color(for: entry.providerId)
        let fraction = total > 0 ? Double(entry.tokens) / Double(total) : 0
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                Text(ProviderPalette.glyph(forId: entry.providerId))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(color)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.16)))
                Text(providerName(entry.providerId)).font(Theme.Font.body)
                Spacer()
                if let cost = appModel.estimatedCostByProvider[entry.providerId] {
                    Text("$" + String(format: "%.2f", (cost as NSDecimalNumber).doubleValue))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Text(TokenAnalytics.compactTokens(entry.tokens))
                    .font(Theme.Font.metricMedium)
                    .monospacedDigit()
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            HStack(spacing: Theme.Space.sm) {
                ShareBar(fraction: fraction, color: color)
                if let analytics = byProvider[entry.providerId] {
                    DailyTokensAreaChart(
                        points: TrendSeries.dailyTotals(analytics, lastDays: 14).reversed(),
                        color: color
                    )
                    .frame(width: 70, height: 18)
                }
            }
        }
    }

    // MARK: - Linha 4: cotas

    /// As cinco janelas mais apertadas entre todos os providers. Estava só na aba Visão
    /// geral, embora seja uma das coisas que o dono quer ver primeiro.
    private func quotaStrip() -> some View {
        var worst: [(provider: UsageProvider, window: QuotaWindow, remaining: Double)] = []
        for provider in appModel.orderedProviders {
            guard let snapshot = appModel.snapshotsByProvider[provider.id],
                  appModel.errorKindByProvider[provider.id] != .notConfigured else { continue }
            for window in snapshot.quotas {
                guard let remaining = QuotaPresentation.remainingFraction(window.shape) else { continue }
                worst.append((provider, window, remaining))
            }
        }
        let top = worst.sorted { $0.remaining < $1.remaining }.prefix(5)
        return Group {
            if !top.isEmpty {
                DashboardCard {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        SectionHeader(L("Cotas mais apertadas"))
                        ForEach(Array(top.enumerated()), id: \.offset) { _, entry in
                            let danger = QuotaPresentation.color(remaining: entry.remaining)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: Theme.Space.sm) {
                                    Text("\(entry.provider.displayName) · \(WindowLabelCatalog.displayLabel(entry.window.label))")
                                        .font(.system(size: 11))
                                    Spacer()
                                    if let reset = QuotaPresentation.resetText(entry.window.shape) {
                                        Text(reset).font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                    Text(QuotaPresentation.remainingText(entry.window.shape))
                                        .font(.system(size: 11, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(danger)
                                }
                                QuotaCapsuleBar(remaining: entry.remaining, color: danger, height: 6)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footnote: some View {
        Text(L("Codex: estatísticas da conta (API). Claude Code e OpenCode: estimativa local dos transcritos/banco desta máquina, incluindo tokens de cache."))
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
    }
}
```

- [ ] **Step 2: Trocar a tela antiga pela nova**

Em `Sources/OkTally/UI/MainWindowView.swift`, no `switch pane` do `detail`, o caso `.analytics` passa a ser:

```swift
                    case .analytics:
                        AnalyticsDashboardView(appModel: appModel)
```

Em seguida remova a `private struct AnalyticsScreen` inteira (ela existia só para esse caso) — o compilador vai apontar se sobrou algum uso.

- [ ] **Step 3: Compilar**

Run: `swift build 2>&1 | tail -15`
Expected: `Build complete!`. Se acusar `AnalyticsScreen` não usada mas ainda referenciada, sobrou uma chamada.

- [ ] **Step 4: Renderizar e olhar**

Substitua, em `Tests/OkTallyTests/ReadmeAssetRenderer.swift`, o bloco que renderiza `AnalyticsSection(analytics: demoAnalytics())` por:

```swift
        try write(view: AnalyticsDashboardView(appModel: model)
                    .padding(24)
                    .frame(width: 860)
                    .background(Color(nsColor: .windowBackgroundColor)),
                  to: "analytics.png")
```

Run: `RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer 2>&1 | tail -5 && open docs/assets/analytics.png`
Expected: herói à esquerda com número grande e área, streak e pico à direita, tendência empilhada colorida ocupando a largura toda, linhas por provedor com barra de participação, donut e faixa de cotas. Se algum bloco vier vazio, o `demoModel()` do harness não popula aquele campo — ajuste o harness, não a view.

- [ ] **Step 5: Commit**

```bash
git add Sources/OkTally/UI/AnalyticsDashboardView.swift Sources/OkTally/UI/MainWindowView.swift Tests/OkTallyTests/ReadmeAssetRenderer.swift
git commit -m "feat(ui): aba Análise vira grade bento com Swift Charts"
```

---

### Task 9: Visão geral e detalhe sobre os componentes novos

**Files:**
- Modify: `Sources/OkTally/UI/MainWindowView.swift` (`OverviewScreen`, `KPICard`, `ProviderOverviewCard`, `ProviderDetailScreen`)
- Create: `Sources/OkTally/UI/DesignSystem/ProviderSidebarRow.swift`

**Interfaces:**
- Consumes: `DashboardCard`, `StatTile`, `SectionHeader`, `Theme`, `ProviderPalette`, `QuotaPresentation`.
- Produces: `struct ProviderSidebarRow: View` — `init(providerId: String, name: String, statusColor: Color, statusHelp: String)`.

- [ ] **Step 1: Extrair a linha de sidebar compartilhada**

Crie `Sources/OkTally/UI/DesignSystem/ProviderSidebarRow.swift`:

```swift
// Sources/OkTally/UI/DesignSystem/ProviderSidebarRow.swift
import SwiftUI

/// Linha de sidebar com chip colorido e ponto de status. Estava duplicada entre
/// `MainWindowView.sidebarRow` e `PreferencesView.sidebarRow`.
struct ProviderSidebarRow: View {
    let providerId: String
    let name: String
    let statusColor: Color
    var statusHelp: String = ""

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(ProviderPalette.color(for: providerId).opacity(0.16))
                    .frame(width: 20, height: 20)
                Text(ProviderPalette.glyph(forId: providerId))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(ProviderPalette.color(for: providerId))
            }
            Text(name).font(Theme.Font.body)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .help(statusHelp)
        }
    }
}
```

- [ ] **Step 2: Usar a linha compartilhada na janela principal**

Em `MainWindowView`, substitua o corpo de `sidebarRow(_:snapshot:)` por:

```swift
    private func sidebarRow(_ provider: UsageProvider, snapshot: ProviderSnapshot) -> some View {
        ProviderSidebarRow(
            providerId: provider.id,
            name: provider.displayName,
            statusColor: QuotaPresentation.providerColor(snapshot)
        )
    }
```

- [ ] **Step 3: Trocar `KPICard` por `StatTile` e dar hierarquia ao gargalo**

Em `OverviewScreen.kpiRow`, troque as três chamadas de `KPICard` por `StatTile`, com o gargalo em destaque:

```swift
    private var kpiRow: some View {
        HStack(spacing: Theme.Space.md) {
            StatTile(title: L("Provedores"), value: "\(entries.count)", caption: L("com dados"))
                .frame(width: 150)
            if let worst = worstOverall {
                StatTile(
                    title: L("Gargalo"),
                    value: "\(Int((worst.remaining * 100).rounded()))%",
                    caption: "\(worst.provider.displayName) · \(WindowLabelCatalog.displayLabel(worst.window.label))",
                    tint: QuotaPresentation.color(remaining: worst.remaining),
                    emphasis: .hero
                )
            }
            if let cost = totalEstimatedCost {
                StatTile(
                    title: L("Custo estimado"),
                    value: "$" + String(format: "%.2f", (cost as NSDecimalNumber).doubleValue),
                    caption: L("últimos 30 dias")
                )
                .frame(width: 170)
            }
        }
    }
```

Em seguida remova a `private struct KPICard` inteira.

- [ ] **Step 4: Trocar o fundo manual dos cards por `DashboardCard`**

Em `ProviderOverviewCard.body` e em `ProviderDetailScreen.windowRow(_:)`, remova os pares `.background(RoundedRectangle...)` + `.overlay(RoundedRectangle...strokeBorder...)` e envolva o conteúdo em `DashboardCard { ... }`. O mesmo vale para o card de "USO — 7 DIAS" em `ProviderDetailScreen`, cujo título passa a usar `SectionHeader(L("Uso — 7 dias"))`.

- [ ] **Step 5: Compilar e verificar visualmente**

Run: `swift build 2>&1 | tail -10 && RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer 2>&1 | tail -5 && open docs/assets/overview.png`
Expected: build limpo; na imagem, o KPI de gargalo aparece tingido e maior que os vizinhos, e os cards de provider mantêm o mesmo raio e borda do resto.

- [ ] **Step 6: Rodar a suíte**

Run: `swift test 2>&1 | tail -10`
Expected: tudo passa.

- [ ] **Step 7: Commit**

```bash
git add Sources/OkTally/UI/MainWindowView.swift Sources/OkTally/UI/DesignSystem/ProviderSidebarRow.swift
git commit -m "refactor(ui): Visão geral e detalhe sobre o design system"
```

---

### Task 10: Popover — tokens e faixa "hoje"

**Files:**
- Modify: `Sources/OkTally/UI/PopoverView.swift`

**Interfaces:**
- Consumes: `Theme`, `SectionHeader`, `DailyTokensAreaChart`, `TrendSeries`, `AppModel.aggregatedAnalytics`.
- Produces: nada novo — `PopoverContentView` mantém a assinatura, o harness de render continua funcionando.

- [ ] **Step 1: Adicionar a faixa "hoje" no topo do conteúdo**

Em `PopoverContentView`, adicione a propriedade e insira-a como primeiro elemento do `VStack` do `body` (antes do herói de cota):

```swift
    /// Volume de hoje + 14 dias, antes das cotas. A cota continua tendo prioridade: se o
    /// espaço apertar, esta faixa é a primeira a sair.
    @ViewBuilder private var todayStrip: some View {
        if let analytics = appModel.aggregatedAnalytics {
            let totals = TrendSeries.dailyTotals(analytics, lastDays: 14)
            let today = totals.first?.tokens ?? 0
            if today > 0 {
                HStack(spacing: Theme.Space.sm) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(L("Hoje"))
                        Text(TokenAnalytics.compactTokens(today))
                            .font(Theme.Font.metricMedium)
                            .monospacedDigit()
                    }
                    DailyTokensAreaChart(points: totals.reversed(), color: .accentColor)
                        .frame(height: 28)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .glassChrome()
                .padding(.horizontal, Theme.Space.md)
            }
        }
    }
```

- [ ] **Step 2: Carregar a análise ao abrir o popover**

Ainda em `PopoverContentView`, acrescente ao `body` (no mesmo nível dos outros modificadores):

```swift
        .task { await appModel.loadAllAnalyticsIfStale() }
```

- [ ] **Step 3: Compilar e renderizar**

Run: `swift build 2>&1 | tail -10 && RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer 2>&1 | tail -5 && open docs/assets/popover.png`
Expected: a faixa "hoje" aparece acima do card de cota mais crítica, sem empurrar o conteúdo para fora dos 480 pt de altura. Se empurrar, remova a faixa — a cota tem prioridade, como diz o spec.

- [ ] **Step 4: Commit**

```bash
git add Sources/OkTally/UI/PopoverView.swift
git commit -m "feat(ui): popover ganha faixa de uso de hoje"
```

---

### Task 11: Preferências — Form agrupado, auto-save e limiares novos

**Files:**
- Modify: `Sources/OkTally/UI/PreferencesView.swift` (`GeneralPane`, linhas ~445-529; `PreferencesView.body`, linhas ~40-70)

**Interfaces:**
- Consumes: `FieldCommit.lowBalance(_:)` da Task 4; `PreferencesStore.alertPercentThresholds`, `.alertLowBalanceThreshold`, `.alertsEnabled`; `ProviderSidebarRow` da Task 9.
- Produces: nada consumido por tasks posteriores.

- [ ] **Step 1: Ampliar as opções de limiar**

Em `GeneralPane`, troque a constante:

```swift
    /// 50/70/80/90/100 — nenhuma migração necessária: `alertPercentThresholds` já
    /// persiste uma lista arbitrária de frações, e quem tinha 70/90/100 continua igual.
    private static let percentOptions: [Double] = [0.5, 0.7, 0.8, 0.9, 1.0]
```

- [ ] **Step 2: Converter o pane Geral para `Form` agrupado**

Substitua o `body` de `GeneralPane` por:

```swift
    var body: some View {
        Form {
            Section(L("Barra de menu")) {
                if appModel.menuBarPins.isEmpty {
                    Text(L("Nada fixado — a barra mostra automaticamente a janela mais próxima do limite."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(appModel.menuBarPins, id: \.stored) { pin in
                            HStack(spacing: Theme.Space.sm) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(ProviderPalette.glyph(forId: pin.providerId))
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(ProviderPalette.color(for: pin.providerId))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 5)
                                        .fill(ProviderPalette.color(for: pin.providerId).opacity(0.16)))
                                Text("\(providerName(pin.providerId)) · \(WindowLabelCatalog.displayLabel(pin.windowLabel))")
                                    .font(Theme.Font.body)
                                Spacer()
                                Button {
                                    appModel.menuBarPins.removeAll { $0.stored == pin.stored }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onMove { source, destination in
                            appModel.menuBarPins.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .frame(height: CGFloat(appModel.menuBarPins.count) * 30 + 12)
                    .scrollDisabled(true)
                }
                Text(L("Arraste para reordenar. Fixe janelas pelo alfinete no menu do OkTally — cada uma vira um número colorido na barra."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Alertas")) {
                Toggle(L("Notificações de cota"), isOn: $alertsEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: alertsEnabled) { _, newValue in
                        preferencesStore.alertsEnabled = newValue
                    }
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(L("Avisar quando o uso cruzar:")).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(Self.percentOptions, id: \.self) { step in
                            thresholdChip(step)
                        }
                    }
                }
                HStack(spacing: Theme.Space.sm) {
                    Text(L("Saldo baixo (USD):")).font(.caption).foregroundStyle(.secondary)
                    TextField("5.00", text: $lowBalanceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit(saveLowBalance)
                    if savedFlash {
                        Text(L("Salvo")).font(.caption).foregroundStyle(.green).transition(.opacity)
                    }
                }
            }
            .disabled(!alertsEnabled)
            .opacity(alertsEnabled ? 1 : 0.5)

            Section(L("Atualizações")) {
                if let update = appModel.availableUpdate {
                    HStack(spacing: Theme.Space.sm) {
                        Label(LF("Versão %@ disponível", update.version), systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(L("Abrir no GitHub")) { NSWorkspace.shared.open(update.url) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                } else {
                    Text(L("Você está na versão mais recente."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            alertsEnabled = preferencesStore.alertsEnabled
            percentSteps = Set(preferencesStore.alertPercentThresholds)
            lowBalanceText = String(format: "%.2f", preferencesStore.alertLowBalanceThreshold)
        }
    }

    /// Chip selecionável — substitui a checkbox solta.
    private func thresholdChip(_ step: Double) -> some View {
        let selected = percentSteps.contains(step)
        return Button {
            if selected { percentSteps.remove(step) } else { percentSteps.insert(step) }
            preferencesStore.alertPercentThresholds = percentSteps.sorted()
        } label: {
            Text("\(Int(step * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.xs)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.25) : Theme.surface()))
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.6) : Theme.border()))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 3: Trocar o salvamento manual por auto-save**

Ainda em `GeneralPane`, acrescente o estado do selo e reescreva `saveLowBalance` usando `FieldCommit`:

```swift
    @State private var savedFlash = false

    /// Auto-save: o botão "Salvar" saiu. Valor inválido não grava e não apaga o antigo.
    private func saveLowBalance() {
        guard let value = FieldCommit.lowBalance(lowBalanceText) else {
            lowBalanceText = String(format: "%.2f", preferencesStore.alertLowBalanceThreshold)
            return
        }
        preferencesStore.alertLowBalanceThreshold = value
        lowBalanceText = String(format: "%.2f", value)
        withAnimation { savedFlash = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { savedFlash = false }
        }
    }
```

Remova o antigo `percentBinding(_:)` e o botão `Button(L("Salvar"), action: saveLowBalance)` que ficava ao lado do campo.

- [ ] **Step 4: Deixar a janela redimensionável**

Em `PreferencesView.body`, troque a linha `.frame(width: 640, height: 460)` por:

```swift
        .frame(minWidth: 680, idealWidth: 720, minHeight: 520, idealHeight: 560)
```

E troque o corpo de `sidebarRow(_:)` pelo componente compartilhado:

```swift
    private func sidebarRow(_ id: String) -> some View {
        ProviderSidebarRow(
            providerId: id,
            name: providerName(id),
            statusColor: statusDotColor(id),
            statusHelp: statusDotHelp(id)
        )
    }
```

- [ ] **Step 5: Mostrar na sidebar quantas contas precisam de atenção**

Em `PreferencesView`, a `Section(L("Contas"))` da sidebar passa a exibir a contagem:

```swift
                Section {
                    ForEach(providerIds, id: \.self) { id in
                        sidebarRow(id).tag(PreferencesPane.provider(id))
                    }
                } header: {
                    HStack {
                        Text(L("Contas"))
                        Spacer()
                        let attention = providerIds.filter { appModel.errorKindByProvider[$0] == .needsReauth }.count
                        if attention > 0 {
                            Text("\(attention)")
                                .font(.system(size: 9, weight: .bold))
                                .monospacedDigit()
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.25)))
                                .foregroundStyle(.orange)
                                .help(L("Contas com credencial expirada"))
                        }
                    }
                }
```

- [ ] **Step 6: Compilar**

Run: `swift build 2>&1 | tail -15`
Expected: `Build complete!`. Erro provável: `onChange(of:) { _, newValue in }` exige a assinatura de duas casas — no alvo macOS 26 é a correta; se o compilador reclamar de aridade, algum outro `onChange` do arquivo ainda usa a forma antiga de um parâmetro e precisa ser migrado junto.

- [ ] **Step 7: Rodar a suíte**

Run: `swift test 2>&1 | tail -10`
Expected: tudo passa, incluindo `FieldCommitTests`.

- [ ] **Step 8: Commit**

```bash
git add Sources/OkTally/UI/PreferencesView.swift
git commit -m "feat(ui): Preferências com Form agrupado, auto-save e limiares 50–100%"
```

---

### Task 12: Scaffold dos painéis de provider

**Files:**
- Create: `Sources/OkTally/UI/ProviderPaneScaffold.swift`
- Modify: `Sources/OkTally/UI/PreferencesView.swift` (`paneHeader`, `claudePane`, `codexPane`, `superGrokPane`, `cursorPane`, `copilotPane`, `antigravityPane`, `keyPane`, `minimaxPane`, `mimoPane`)

**Interfaces:**
- Consumes: `Theme`, `ProviderPalette`, `FieldCommit.sanitized(_:previous:)`.
- Produces: `struct ProviderPaneScaffold<Connection: View, Details: View>: View` — `init(providerId: String, name: String, status: ProviderPaneStatus, @ViewBuilder connection: () -> Connection, @ViewBuilder details: () -> Details)` e `enum ProviderPaneStatus { case connected(String), needsAttention(String), notConfigured(String) }`.

- [ ] **Step 1: Criar o scaffold**

Crie `Sources/OkTally/UI/ProviderPaneScaffold.swift`:

```swift
// Sources/OkTally/UI/ProviderPaneScaffold.swift
import SwiftUI

/// Estado do provider, exibido como pill em vez do ponto minúsculo de antes.
enum ProviderPaneStatus {
    case connected(String)
    case needsAttention(String)
    case notConfigured(String)

    var text: String {
        switch self {
        case .connected(let t), .needsAttention(let t), .notConfigured(let t): return t
        }
    }

    var tint: Color {
        switch self {
        case .connected: return .green
        case .needsAttention: return .orange
        case .notConfigured: return .secondary
        }
    }
}

/// Casca comum dos dez painéis de provider, que antes montavam cabeçalho e botões cada
/// um do seu jeito.
struct ProviderPaneScaffold<Connection: View, Details: View>: View {
    let providerId: String
    let name: String
    let status: ProviderPaneStatus
    @ViewBuilder var connection: Connection
    @ViewBuilder var details: Details

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Space.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(ProviderPalette.color(for: providerId).opacity(0.16))
                            .frame(width: 40, height: 40)
                        Text(ProviderPalette.glyph(forId: providerId))
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(ProviderPalette.color(for: providerId))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.system(size: 16, weight: .bold))
                        Text(status.text)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(status.tint)
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(status.tint.opacity(0.15)))
                    }
                    Spacer()
                }
            }
            Section(L("Conexão")) { connection }
            Section { details }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Migrar um pane simples primeiro (Codex) para validar o formato**

Em `PreferencesView`, `codexPane` passa a ser:

```swift
    private var codexPane: some View {
        ProviderPaneScaffold(
            providerId: "codex",
            name: providerName("codex"),
            status: codexLoggedIn ? .connected(L("Conectado")) : .notConfigured(L("Não conectado"))
        ) {
            if codexLoggedIn {
                Button(L("Sair")) { logout(providerId: "codex", flag: $codexLoggedIn) }.buttonStyle(.bordered)
            } else {
                Button(L("Entrar…")) { login(config: CodexOAuth.config, flag: $codexLoggedIn) }
                    .buttonStyle(.borderedProminent)
            }
        } details: {
            Text(L("Estatísticas de uso vêm da API da conta."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
```

Run: `swift build 2>&1 | tail -10 && echo OK`
Expected: `Build complete!` antes de migrar os outros nove.

- [ ] **Step 3: Migrar o pane do Claude, que é o mais complexo**

`claudePane` tem estado extra (a sessão de código colado). O fluxo não muda — só a casca:

```swift
    private var claudePane: some View {
        ProviderPaneScaffold(
            providerId: "claude",
            name: providerName("claude"),
            status: claudeLoggedIn ? .connected(L("Conectado")) : .notConfigured(L("Não conectado"))
        ) {
            HStack {
                if claudeLoggedIn {
                    Button(L("Sair")) {
                        logout(providerId: "claude", flag: $claudeLoggedIn)
                        claudeSession = nil
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(L("Entrar…")) { beginClaudeLogin() }
                        .buttonStyle(.borderedProminent)
                    Button(L("Importar do Claude Code")) {
                        statusMessage = onImportClaudeLegacy()
                            ? L("Login importado.")
                            : L("Nenhum login do Claude Code encontrado.")
                        claudeLoggedIn = tokenStore.load(providerId: "claude") != nil
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            if claudeSession != nil {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(L("Autorize no navegador, copie o código e cole abaixo:"))
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("CÓDIGO#STATE", text: $claudePastedCode).textFieldStyle(.roundedBorder)
                    HStack {
                        Button(L("Concluir")) { completeClaudeLogin() }
                            .buttonStyle(.borderedProminent)
                            .disabled(claudePastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button(L("Cancelar")) {
                            claudeSession = nil
                            claudePastedCode = ""
                            statusMessage = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        } details: {
            Text(L("O uso de cota vem da conta; o volume em tokens é estimado dos transcritos locais."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
```

- [ ] **Step 4: Migrar os panes de detecção automática**

`cursorPane`, `copilotPane` e `antigravityPane` têm a mesma forma: nenhuma ação de conexão, só um texto. Modelo, com Cursor preenchido — repita trocando id, nome e textos pelos que cada pane já usa hoje:

```swift
    private var cursorPane: some View {
        ProviderPaneScaffold(
            providerId: "cursor",
            name: providerName("cursor"),
            status: .connected(L("Lê a sessão do app Cursor automaticamente"))
        ) {
            Text(L("Nada a configurar — se o app Cursor estiver logado nesta máquina, o uso aparece sozinho."))
                .font(.caption).foregroundStyle(.secondary)
        } details: {
            EmptyView()
        }
    }
```

Para `copilotPane`, o status depende de `CopilotTokenReader().firstToken() != nil`: conectado → `.connected(L("Login do Copilot/gh CLI detectado"))`, senão `.notConfigured(L("Nenhum login do Copilot/gh CLI encontrado"))`. Para `antigravityPane`, idem com `AntigravityTokenReader().readTokens() != nil` e os textos do Antigravity que já estão no arquivo.

- [ ] **Step 5: Migrar SuperGrok, MiniMax e MiMo**

`superGrokPane` segue o formato do Codex (botão Entrar/Sair em `connection`), mas o bloco do device code vai para `details`:

```swift
        } details: {
            if let info = superGrokDeviceCode {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(LF("Abra %@ e digite:", info.verificationURL.absoluteString))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(info.userCode).font(.title3.monospaced()).textSelection(.enabled)
                }
            }
        }
```

`minimaxPane` e `mimoPane` mantêm todos os campos que já possuem (região, allowance, used) — mova os controles para `connection` e os textos explicativos para `details`, sem alterar nenhum binding.

Em seguida remova a função `paneHeader(_:status:active:)`, agora sem uso.

- [ ] **Step 6: Dar auto-save às chaves de API**

`keyPane` passa a gravar sozinho, sem botão:

```swift
    private func keyPane(_ id: String, text: Binding<String>, status: String, save: @escaping () -> Void) -> some View {
        ProviderPaneScaffold(
            providerId: id,
            name: providerName(id),
            status: text.wrappedValue.isEmpty ? .notConfigured(status) : .connected(status)
        ) {
            SecureField("API Key", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 380)
                .onSubmit(save)
        } details: {
            Text(L("A chave fica no Keychain desta máquina, nunca em disco."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
```

E, no `saveSecret`, proteja a gravação com `FieldCommit` para que blur com campo vazio não apague credencial. Localize a função com `grep -n "func saveSecret" Sources/OkTally/UI/PreferencesView.swift` e envolva o corpo:

```swift
    private func saveSecret(_ label: String, previous: String, raw: String, _ body: () throws -> Void) {
        guard FieldCommit.sanitized(raw, previous: previous) != nil else { return }
        do {
            try body()
            statusMessage = LF("%@ salvo.", label)
        } catch {
            statusMessage = LF("Falha ao salvar %@: %@", label, error.localizedDescription)
        }
    }
```

Ajuste as três chamadas de `saveSecret` (openrouter, opencode, minimax) para passar `previous:` e `raw:`.

- [ ] **Step 7: Compilar e rodar a suíte**

Run: `swift build 2>&1 | tail -10 && swift test 2>&1 | tail -10`
Expected: build limpo, todos os testes passando.

- [ ] **Step 8: Verificar visualmente**

Acrescente ao `ReadmeAssetRenderer`, dentro de `test_renderReadmeAssets`:

```swift
        try write(view: ProviderPaneScaffold(
                        providerId: "codex",
                        name: "Codex",
                        status: .connected("Conectado"),
                        connection: { Button("Sair") {}.buttonStyle(.bordered) },
                        details: { Text("Estatísticas de uso vêm da API da conta.").font(.caption) })
                    .frame(width: 520, height: 320)
                    .background(Color(nsColor: .windowBackgroundColor)),
                  to: "preferences-provider.png")
```

Run: `RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer 2>&1 | tail -5 && open docs/assets/preferences-provider.png`
Expected: cabeçalho com ícone, nome e pill verde, seção "Conexão" com o botão, seção de detalhes — tudo em cartões agrupados do `Form`.

- [ ] **Step 9: Commit**

```bash
git add Sources/OkTally/UI/ProviderPaneScaffold.swift Sources/OkTally/UI/PreferencesView.swift Tests/OkTallyTests/ReadmeAssetRenderer.swift
git commit -m "refactor(ui): dez painéis de provider sobre um scaffold único"
```

---

## Fase 4 — Acabamento

### Task 13: Liquid Glass no cromo

**Files:**
- Modify: `Sources/OkTally/UI/DesignSystem/Theme.swift` (`glassChrome`)

**Interfaces:**
- Consumes: nada novo.
- Produces: `glassChrome()` passa a usar a API nativa de vidro, mantendo a mesma assinatura — nenhum chamador muda.

- [ ] **Step 1: Descobrir a assinatura real da API no SDK instalado**

Não adivinhe o nome. Verifique:

Run: `grep -rn "func glassEffect" $(xcrun --show-sdk-path)/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/*.swiftinterface 2>/dev/null | head -5`

Se não retornar nada, mantenha `.regularMaterial` e pule para o Step 4 — material já é o comportamento correto e o app fica pronto do mesmo jeito.

- [ ] **Step 2: Aplicar a API encontrada**

Se o passo anterior mostrou a assinatura, troque o corpo de `glassChrome()` por ela, mantendo o mesmo `RoundedRectangle` como forma. Exemplo do formato esperado, a ser confirmado contra o que o `grep` retornou:

```swift
    func glassChrome() -> some View {
        self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
```

- [ ] **Step 3: Compilar**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`. Se falhar, reverta para `.regularMaterial` — vidro é acabamento, não pode bloquear a entrega.

- [ ] **Step 4: Commit**

```bash
git add Sources/OkTally/UI/DesignSystem/Theme.swift
git commit -m "feat(ui): Liquid Glass no cromo do popover e dos headers"
```

---

### Task 14: Entrega — assets, build e instalação

**Files:**
- Modify: `docs/assets/*.png` (gerados)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: tudo anterior.
- Produces: app instalado em `/Applications`.

- [ ] **Step 1: Regerar todos os assets e conferir cada um**

Run: `RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer 2>&1 | tail -5 && open docs/assets/`
Expected: `popover.png`, `overview.png`, `analytics.png`, `preferences-provider.png` e `menubar.png` atualizados. Olhe todos. Corte, texto truncado ou bloco vazio é defeito — volte à task correspondente.

- [ ] **Step 2: Rodar a suíte inteira uma última vez**

Run: `swift test 2>&1 | tail -15`
Expected: todos passam.

- [ ] **Step 3: Registrar o redesign no CHANGELOG**

Em `CHANGELOG.md`, na seção não lançada criada na Task 1:

```markdown
### Adicionado
- Aba Análise redesenhada como dashboard: bloco-herói com o uso de hoje, gráfico de
  barras empilhado por provedor (30 d / 90 d / 12 m), donut de participação e faixa das
  cotas mais apertadas.
- Heatmap de uso agora preenche a largura disponível e ganhou legenda.

### Alterado
- Preferências reconstruídas com formulários agrupados nativos; campos salvam sozinhos
  (os botões "Salvar" saíram) e os limiares de alerta agora incluem 50 % e 80 %.
- Popover, Visão geral e Preferências passam a compartilhar o mesmo design system.
```

- [ ] **Step 4: Construir e instalar**

```bash
bash Scripts/build_app.sh
pkill -x OkTally 2>/dev/null || true
mv /Applications/OkTally.app ~/.Trash/OkTally-pre-redesign-$(date +%s).app
cp -R .build/OkTally.app /Applications/OkTally.app
open /Applications/OkTally.app
```

Expected: app abre na barra de menu. Confirme com `pgrep -x OkTally`.

- [ ] **Step 5: Commit**

```bash
git add docs/assets CHANGELOG.md
git commit -m "docs: assets e changelog do redesign"
```

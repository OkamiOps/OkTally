# OkTally — previsão de esgotamento de cotas — plano de implementação

> **Para execução:** implementar task por task, em TDD, usando a skill
> `executing-plans`. Não publicar release nem fazer push sem autorização explícita.

**Objetivo:** mostrar se uma cota semanal ou mensal deve acabar antes da renovação,
comparando o ritmo líquido das últimas 24 horas com o ritmo seguro até o reset.

**Arquitetura:** `QuotaWindow` declara explicitamente a cadência renovável; um engine
puro transforma a janela atual e seus snapshots exatos em uma previsão reproduzível;
o `AppModel` consulta as últimas 24h fora da main thread, publica os resultados e aplica
a seleção automática/manual; SwiftUI apenas apresenta o resultado pronto em duas barras
no popover e em um gráfico Swift Charts no detalhe do provider.

**Stack:** Swift 5 mode sobre Swift tools 6.2, macOS 26, SwiftUI, Swift Charts, GRDB,
XCTest. Nenhuma dependência nova e nenhuma migração de banco.

## Restrições globais

- A previsão é sempre uma estimativa baseada na variação líquida das últimas 24h.
- Apenas percentuais reais com `resetAt` futuro e cadência `.weekly` ou `.monthly` são
  elegíveis. Janelas de 5h, saldo, metered e `.estimated` ficam fora.
- `QuotaWindow` mantém compatibilidade com snapshots antigos: `renewalCadence` é opcional
  e o initializer usa `nil` por padrão.
- A identidade persistida continua sendo `providerId + window.label`; rótulos amigáveis
  são apenas apresentação.
- Não inventar reset para MiMo: o payload atual fornece percentual, mas não uma data real.
  Ele só entra quando o provider passar a produzir um `resetAt` mensal verdadeiro.
- Todo texto visível passa por `L(_:)`/`LF(_:_:)`; traduções inglesas entram em
  `Sources/OkTally/Resources/en.lproj/Localizable.strings`.
- Cores vêm de `ProviderPalette`, `UsageColorScale` e `Theme`; não criar paleta paralela.
- Não consultar SQLite dentro de `View.body` e não bloquear a main thread.
- Cada task termina com testes focados e commit local. A suíte completa fica para a
  validação final.

---

## Task 1 — Declarar cadência renovável nos snapshots reais

**Files:**

- Modify: `Sources/OkTally/Core/ProviderSnapshot.swift`
- Modify: `Sources/OkTally/Plugins/Claude/ClaudeUsageProvider.swift`
- Modify: `Sources/OkTally/Plugins/Codex/CodexUsageProvider.swift`
- Modify: `Sources/OkTally/Plugins/Cursor/CursorUsageProvider.swift`
- Modify: `Sources/OkTally/Plugins/Cursor/GrokBotUsageProvider.swift`
- Modify: `Sources/OkTally/Plugins/SuperGrok/SuperGrokUsageProvider.swift`
- Modify: `Sources/OkTally/Plugins/MiniMax/MiniMaxUsageProvider.swift`
- Modify: `Sources/OkTally/Plugins/Antigravity/AntigravityUsageProvider.swift`
- Test: provider tests correspondentes em `Tests/OkTallyTests/`
- Test: `Tests/OkTallyTests/QuotaShapeTests.swift`

**Interfaces produzidas:**

```swift
enum RenewalCadence: String, Codable, Equatable {
    case weekly
    case monthly
}

struct QuotaWindow: Codable, Equatable {
    let label: String
    let shape: QuotaShape
    let renewalCadence: RenewalCadence?

    init(label: String, shape: QuotaShape, renewalCadence: RenewalCadence? = nil)
}
```

- [ ] **1.1 — Testes falhando de compatibilidade.** Em `QuotaShapeTests`, validar que
  uma janela nova faz round-trip com `.weekly` e que JSON legado sem o campo decodifica
  com `renewalCadence == nil`.
- [ ] **1.2 — Implementar o contrato.** Adicionar enum, propriedade e initializer com
  default `nil`; manter Codable sintetizado e confirmar que snapshots antigos continuam
  decodificando.
- [ ] **1.3 — Marcar apenas janelas reais.** Ajustar e testar:
  - Claude `weekly` e `weekly-opus` → `.weekly`; `5h` → `nil`;
  - Codex → `.weekly` somente quando `limitWindowSeconds == 604800`;
  - Cursor `percent` → `.monthly`; `balance` → `nil`;
  - GrokBot e SuperGrok `weekly` → `.weekly`;
  - MiniMax `weekly` → `.weekly`; `5h` → `nil`;
  - Antigravity → `.weekly` somente quando o bucket é semanal;
  - MiMo permanece sem cadência enquanto o reset continuar sintético.
- [ ] **1.4 — Rodar testes focados.** Executar os testes dos oito providers alterados e
  `QuotaShapeTests`. Esperado: todos verdes e nenhum teste antigo exigindo mudanças nos
  call sites graças ao default `nil`.
- [ ] **1.5 — Commit local.** `feat(forecast): mark renewable quota cadence`

---

## Task 2 — Construir o engine puro de previsão

**Files:**

- Create: `Sources/OkTally/Core/UsageForecast.swift`
- Modify: `Sources/OkTally/Core/UsageHistory.swift`
- Create: `Tests/OkTallyTests/UsageForecastEngineTests.swift`
- Modify: `Tests/OkTallyTests/UsageHistoryTests.swift`

**Interfaces produzidas:**

```swift
struct ForecastWindowID: Hashable, Equatable {
    let providerId: String
    let windowLabel: String
}

enum UsageForecastState: Equatable {
    case slowDown
    case onPace
    case canAccelerate
    case noExhaustion
    case collecting(observedHours: Double, sampleCount: Int)
    case unavailable
}

struct UsageForecast: Equatable {
    let id: ForecastWindowID
    let cadence: RenewalCadence
    let currentUsedPercent: Double
    let samples: [UsageHistoryPoint]
    let ratePerDay: Double?
    let safeRatePerDay: Double?
    let exhaustionAt: Date?
    let resetAt: Date
    let gap: TimeInterval?
    let state: UsageForecastState
}

enum UsageForecastEngine {
    static func forecast(
        providerId: String,
        current: QuotaWindow,
        snapshots: [ProviderSnapshot],
        now: Date
    ) -> UsageForecast
}
```

- [ ] **2.1 — Extrair série da janela exata.** Primeiro escrever testes para
  `UsageHistory.series(providerId:windowLabel:resetAt:snapshots:)`: selecionar pelo
  provider/label, aceitar diferença de reset de até 60s, ordenar por `fetchedAt`, ignorar
  outro ciclo e preservar amostras repetidas.
- [ ] **2.2 — Escrever a matriz de testes do engine.** Com `now` fixo, cobrir:
  esgotamento antes, dentro de ±6h e depois do reset; ritmo zero; menos de 3h; menos de 6
  amostras; menos de 0,5 ponto após série madura; correção negativa; amostras fora de
  ordem; outro reset; reset ausente/passado; percentual em/maior que 100.
- [ ] **2.3 — Implementar elegibilidade.** Uma helper pura valida cadência, shape
  percentual não estimado e reset futuro. Entrada inelegível retorna `.unavailable`, sem
  data inventada.
- [ ] **2.4 — Implementar cálculo.** Usar somente amostras entre `now - 24h...now`, com
  as fórmulas da especificação. Limitar o percentual apenas para apresentação/cálculo de
  restante; manter o snapshot bruto intacto. `gap = resetAt - exhaustionAt`.
- [ ] **2.5 — Implementar estados.** `gap > 6h` → `.slowDown`; `abs(gap) <= 6h` →
  `.onPace`; `gap < -6h` → `.canAccelerate`; com pelo menos 3h e 6 amostras, ritmo não
  positivo ou variação abaixo de 0,5 ponto → `.noExhaustion`; abaixo dos mínimos de tempo
  ou amostras → `.collecting`.
- [ ] **2.6 — Rodar testes focados.** `swift test --filter UsageForecastEngineTests` e
  `swift test --filter UsageHistoryTests`.
- [ ] **2.7 — Commit local.** `feat(forecast): calculate 24h quota pace`

---

## Task 3 — Persistir e resolver o alvo automático/manual

**Files:**

- Modify: `Sources/OkTally/Core/UsageForecast.swift`
- Modify: `Sources/OkTally/Preferences/PreferencesStore.swift`
- Modify: `Sources/OkTally/App/AppModel.swift`
- Create: `Tests/OkTallyTests/UsageForecastSelectionTests.swift`
- Modify: `Tests/OkTallyTests/PreferencesStoreTests.swift`
- Modify: `Tests/OkTallyTests/AppModelTests.swift`

**Interfaces produzidas:**

```swift
enum ForecastSlot: Equatable, Hashable {
    case automatic
    case window(providerId: String, windowLabel: String)

    var stored: String { get }
    init(stored: String?)
}

enum UsageForecastSelection {
    static func select(
        preferred: ForecastSlot,
        forecasts: [ForecastWindowID: UsageForecast]
    ) -> UsageForecast?
}
```

- [ ] **3.1 — Testar serialização.** Repetir o contrato robusto de `QuotaSlot`: string
  vazia/lixo → `.automatic`; `providerId + \u{1} + label` faz round-trip.
- [ ] **3.2 — Testar seleção automática.** Cobrir maior `gap` positivo; menor folga
  quando todas estão seguras; e, sem previsão numérica, `.collecting` com maior intervalo
  observado.
- [ ] **3.3 — Testar seleção manual.** O alvo existente vence o automático. Alvo ausente
  cai temporariamente para automático sem alterar a preferência persistida.
- [ ] **3.4 — Persistir no store.** Adicionar key `forecastSlot`, getter/setter e testes
  de default/round-trip em `PreferencesStoreTests`.
- [ ] **3.5 — Publicar a preferência no modelo.** Adicionar
  `@Published var forecastSlot` com `didSet` para o store e inicialização no `init`.
  Expor `availableForecastSlots` a partir das janelas atuais elegíveis, sem depender de
  pinos, e `selectedForecast` via resolver puro.
- [ ] **3.6 — Rodar testes focados.** `UsageForecastSelectionTests`,
  `PreferencesStoreTests` e `AppModelTests`.
- [ ] **3.7 — Commit local.** `feat(forecast): add automatic and pinned forecast target`

---

## Task 4 — Recalcular previsões em background no AppModel

**Files:**

- Modify: `Sources/OkTally/App/AppModel.swift`
- Modify: `Tests/OkTallyTests/AppModelTests.swift`

**Interfaces produzidas:**

```swift
@Published private(set)
var forecastsByWindow: [ForecastWindowID: UsageForecast]

func recomputeForecasts(providerId: String, now: Date = Date()) async
func forecasts(providerId: String) -> [UsageForecast]
```

- [ ] **4.1 — Escrever testes de integração do modelo.** Com `FakeStorage`, persistir
  seis ou mais snapshots de um ciclo semanal e confirmar que `recomputeForecasts`
  publica a previsão exata; confirmar também que falha de leitura mantém o último valor.
- [ ] **4.2 — Calcular fora da main thread.** Em `recomputeForecasts`, capturar o snapshot
  atual, consultar `storage.snapshots(providerId:since: now-24h)` e rodar o engine em
  `Task.detached(priority: .utility)`. Ao voltar ao `MainActor`, publicar somente se o
  `fetchedAt` capturado ainda for o snapshot atual, evitando resultado velho sobre novo.
- [ ] **4.3 — Atualizar por provider.** Após `apply(.success)`, disparar recomputação só
  para o provider atualizado. No init, depois do seed persistido, disparar o mesmo fluxo
  para cada provider com snapshot.
- [ ] **4.4 — Mesclar sem apagar outros providers.** Substituir apenas as chaves do
  provider recalculado. Erro de SQLite/decode preserva previsões já publicadas e não vira
  erro do provider.
- [ ] **4.5 — Rodar testes focados.** `swift test --filter AppModelTests`.
- [ ] **4.6 — Commit local.** `feat(forecast): publish forecasts from persisted history`

---

## Task 5 — Apresentar duas barras, gráfico e seletor

**Files:**

- Create: `Sources/OkTally/UI/ForecastBarsView.swift`
- Create: `Sources/OkTally/UI/Charts/ForecastChartView.swift`
- Modify: `Sources/OkTally/UI/PopoverView.swift`
- Modify: `Sources/OkTally/UI/MainWindowView.swift`
- Modify: `Sources/OkTally/UI/PreferencesView.swift`
- Modify: `Sources/OkTally/Resources/en.lproj/Localizable.strings`
- Create: `Tests/OkTallyTests/UsageForecastPresentationTests.swift`
- Create: `Tests/OkTallyTests/ForecastStaticRenderTests.swift`

**Interfaces produzidas:**

```swift
enum UsageForecastPresentation {
    static func headline(_ forecast: UsageForecast, now: Date) -> String
    static func detail(_ forecast: UsageForecast, now: Date) -> String
    static func barFractions(_ forecast: UsageForecast, now: Date) -> (pace: Double, reset: Double)
}

struct ForecastBarsView: View
struct ForecastChartView: View
```

- [ ] **5.1 — Testar apresentação antes da view.** Cobrir copy de todos os estados em PT,
  frações na mesma escala temporal, clamp 0...1 e duração legível. A view não contém
  matemática de previsão.
- [ ] **5.2 — Implementar o card compacto.** Cabeçalho com chip/provider/janela e restante;
  headline semântico; barras `Seu ritmo` e `Renovação` com a mesma escala; rodapé
  `Ritmo 24h`/`Seguro`. Em `.collecting`, substituir as barras por progresso neutro. Em
  automático, `.unavailable` omite o card; alvo manual mostra explicação neutra.
- [ ] **5.3 — Inserir no popover.** Em `PopoverContentView`, renderizar
  `ForecastBarsView` logo depois do `HeroBlock` e antes de `todayStrip`. Preservar largura
  de 360pt, rolagem e a hierarquia visual atual.
- [ ] **5.4 — Implementar o gráfico com Swift Charts.** Plotar percentual restante:
  histórico real das últimas 24h em ciano; projeção tracejada desde agora; linha segura
  tracejada na cor do provider até o reset. Eixo Y fixo 100...0; eixo X até o evento mais
  distante. Abaixo, listar datas, falta/folga, ritmo observado e seguro.
- [ ] **5.5 — Inserir no detalhe.** Em `ProviderDetailScreen`, colocar o gráfico depois do
  herói e antes de `AnalyticsSection`. Se houver várias janelas elegíveis, usar seletor
  local em `@State`; ele não escreve em `forecastSlot`.
- [ ] **5.6 — Adicionar seletor global.** Em Preferências → Geral → Barra de menu, depois
  de `Destaque do menu`, adicionar `Previsão de consumo`: `Automático — maior risco` e
  todas as janelas de `availableForecastSlots`, independentemente dos pinos.
- [ ] **5.7 — Localizar.** Adicionar traduções inglesas para headlines, labels, métricas,
  seletor e estados de coleta/indisponibilidade. Verificar que nenhum `Text` novo usa
  literal não localizado.
- [ ] **5.8 — Render offscreen real.** `ForecastStaticRenderTests` deve usar
  `NSWindow + NSHostingView + cacheDisplay`, em claro e escuro, cobrindo o card a 360pt e
  o detalhe em largura normal/estreita. Validar bitmap não vazio e ausência de clipping;
  salvar anexos/artefatos temporários para inspeção visual durante a execução.
- [ ] **5.9 — Rodar testes focados.** `UsageForecastPresentationTests`,
  `ForecastStaticRenderTests` e `PopoverLayoutTests`.
- [ ] **5.10 — Commit local.** `feat(ui): show quota pace forecast`

---

## Task 6 — Validação integrada e instalação local

**Files:**

- Modify if needed: `Tests/OkTallyTests/ReadmeAssetRenderer.swift` apenas para fixtures
  determinísticas compatíveis com o novo card; não atualizar README/release nesta task.

- [ ] **6.1 — Suíte completa.** Rodar `swift test`. Esperado: todos os testes verdes,
  incluindo os existentes de providers, preferências, popover e notch.
- [ ] **6.2 — Build do app.** Rodar `./Scripts/build_app.sh` e confirmar assinatura da
  `.build/OkTally.app`.
- [ ] **6.3 — Instalar a build fresca.** Substituir `/Applications/OkTally.app` pelo
  artefato novo conforme o fluxo já usado no repo, relançar e verificar versão/build,
  assinatura e processo executando desse caminho.
- [ ] **6.4 — Validar dados reais.** Confirmar que uma janela semanal/mensal com histórico
  suficiente mostra as duas barras; trocar o alvo em Preferências e verificar atualização
  imediata sem relaunch; abrir o detalhe e confirmar gráfico/selector. Janelas 5h e MiMo
  sem reset real não podem aparecer.
- [ ] **6.5 — Inspeção visual.** Conferir os renders claro/escuro e a app instalada para
  contraste, texto cortado, largura de 360pt, e estados `.slowDown`, `.canAccelerate` e
  `.collecting`.
- [ ] **6.6 — Commit de correções estritamente necessárias**, se houver. Não criar release,
  tag ou push sem pedido explícito.

## Critério de conclusão

- A seleção automática encontra a maior falta projetada e a manual fixa Claude semanal
  ou Cursor mensal sem depender do herói/pinos.
- O popover compara esgotamento e renovação em duas barras com escala comum.
- O detalhe mostra histórico, projeção e ritmo seguro sem bloquear a main thread.
- Histórico insuficiente e reset ausente nunca produzem data falsa.
- A suíte completa passa e a build fresca está assinada, instalada e executando em
  `/Applications/OkTally.app`.

## Revisão do plano

- Cobertura da especificação: modelo, engine, seleção, fluxo, popover, detalhe,
  preferências, incerteza, performance e validação estão mapeados.
- Escopo preservado: sem ML, notificações preditivas, Overview agregado, previsão de 5h,
  tabela nova ou dependência nova.
- Risco isolado: thresholds e fórmulas ficam no engine puro, permitindo ajuste posterior
  sem reescrever UI ou persistência.

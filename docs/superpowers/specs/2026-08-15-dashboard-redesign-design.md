# OkTally — Redesign do dashboard (janela principal + popover) — 2026-08-15

Aprovado pelo dono em 2026-08-15. Escopo escolhido: **janela principal + popover da barra**,
ampliado no mesmo dia para incluir **a tela de Preferências**.
Direção visual: **dashboard rico com cor aplicada com critério** — hierarquia forte e
gráficos coloridos por provider, mas ainda um app macOS nativo, não uma página web.

## Problemas que motivam o trabalho

1. **O heatmap não aproveita o espaço.** `TokenHeatmapView` usa célula fixa de 10 pt e
   26 semanas → ~310 pt de largura dentro de um card que na janela passa de 600 pt.
   Sobra metade do card vazia à direita.
2. **Swift Charts nunca foi usado.** O alvo é macOS 13 (`Package.swift`), onde o
   framework já existe. Hoje todo gráfico é `RoundedRectangle`/`Path` na mão
   (`SparklineView`, `QuotaCapsuleBar`, o heatmap) — o app não tira proveito do que a
   plataforma oferece.
3. **Sem hierarquia visual.** Em `AnalyticsSection.statChips` os oito chips têm o mesmo
   tamanho, peso e cor. Nada indica o que importa primeiro. As referências trazidas pelo
   dono sempre têm um bloco-herói e os demais orbitando.
4. **Estilo de card duplicado.** `RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045))`
   com a mesma borda aparece em pelo menos seis pontos entre `MainWindowView` e
   `AnalyticsSection`. Qualquer ajuste de estética exige editar todos.
5. **Cotas ficam longe da análise.** As janelas prestes a estourar só aparecem na aba
   Visão geral, embora seja uma das quatro coisas que o dono quer ver primeiro.

## Restrição de dados (decidida, não negociável neste escopo)

O custo em dólar existe apenas como **total de 30 dias por provider**
(`AppModel.estimatedCostByProvider`). **Não há série diária de custo.** Portanto:

- "Quanto gastei hoje / esta semana" é apresentado em **tokens** (há bucket diário por
  provider em `TokenAnalytics.dailyBuckets`).
- O dinheiro aparece como valor de contexto (custo estimado 30 d), nunca como série
  temporal nem como número diário.
- Custo diário real fica fora deste spec; exigiria gravar preço por dia no SQLite.

## 1. Fundação — `Sources/OkTally/UI/DesignSystem/`

### `Theme.swift`
Tokens, sem lógica:

- Espaçamento: `xs 4`, `sm 8`, `md 12`, `lg 16`, `xl 24`.
- Raios: `small 8`, `medium 12`, `large 16`.
- Tipografia nomeada: `metricHero` (34 pt rounded bold), `metricLarge` (22),
  `metricMedium` (15), `body` (12), `label` (9 pt semibold, tracking 0.5).
- Superfícies: `surface` (opacidade 0.045, como hoje), `surfaceRaised` (0.075),
  `surfaceAccent(Color)` — gradiente diagonal da cor a 0.18 → 0.05.

Todos os valores respeitam claro e escuro por usarem `Color.primary`/`.secondary` e a
cor de identidade, nunca hex fixo de fundo.

### `Components.swift`
- `DashboardCard<Content>` — padding + superfície + borda. Substitui as seis cópias.
- `StatTile` — título/valor/legenda, com variantes `.regular` e `.hero`.
- `SectionHeader` — o texto maiúsculo com tracking, hoje repetido em quatro lugares.
- `DeltaBadge` — variação percentual com ▲/▼ e cor (verde/vermelho/cinza para zero).
- `ShareBar` — barra horizontal de participação, cor de identidade do provider.
- `ProgressRing` — anel reaproveitável (streak atual vs recorde, cota).

### `UI/Charts/`
Gráficos em Swift Charts (`import Charts`), um arquivo por gráfico:

- `DailyTokensAreaChart` — série única com gradiente, usado no herói e no popover.
- `StackedProviderBarChart` — barras diárias empilhadas por provider.
- `ProviderShareDonut` — participação nos últimos 30 dias.

`SparklineView` e `QuotaCapsuleBar` **permanecem**, porque plotam outro dado:
`SparklineView` recebe *percentual de cota usado* (`UsageHistoryPoint.usedPercent`),
enquanto os gráficos novos plotam *tokens por dia*. Os dois convivem — cota e volume são
séries diferentes e não devem ser fundidas.

## 2. Aba Análise — grade bento

De cima para baixo:

**Linha 1 — herói assimétrico.** Card grande (≈60 % da largura) com `surfaceAccent`:
tokens de hoje em `metricHero`, `DeltaBadge` contra ontem, e ao fundo o
`DailyTokensAreaChart` dos últimos 14 dias. Ao lado, empilhados: streak atual com
`ProgressRing` (atual vs recorde) e pico diário.

**Linha 2 — Tendência**, largura total:
- `StackedProviderBarChart` com as cores de `ProviderPalette`, resolvendo distribuição
  entre providers e tendência temporal na mesma figura.
- Segmented control **30 d / 90 d / 12 m**.
- Toggle **Barras ⇄ Heatmap**. O heatmap continua disponível (lê bem streaks) e passa a
  ser **responsivo**: `GeometryReader` deriva o tamanho da célula da largura disponível,
  respeitando um mínimo de 8 pt e um máximo de 16 pt, com rótulos de dia da semana e
  legenda "menos → mais".

**Linha 3 — Por provedor.** Cada linha ganha `ShareBar` (fatia dos 30 d), sparkline
própria e custo estimado; ao lado, `ProviderShareDonut`.

**Linha 4 — Faixa de cotas.** As janelas com menor fração restante entre todos os
providers, com barra e countdown de reset. Reusa `QuotaPresentation`.

O rodapé explicativo das fontes de dados (API do Codex vs estimativa local) é mantido.

## 3. Visão geral e detalhe por provedor

Reconstruídos sobre os mesmos componentes. `KPICard` e o estilo inline de
`ProviderOverviewCard` passam a usar `StatTile`/`DashboardCard`; o KPI de gargalo vira
`.hero` tingido enquanto os demais ficam regulares. As sparklines de cota dos cards de provider continuam sendo
`SparklineView` (é percentual de cota), mas ganham o preenchimento com gradiente do novo
tema para casar com os gráficos de token. A hierarquia bottleneck-first é preservada.

## 4. Popover (360 pt)

Mesmos tokens, densidade maior. Ganha uma faixa "hoje" no topo (número compacto +
`DailyTokensAreaChart` de 14 dias) antes dos cards de cota. A hierarquia cota-primeiro
aprovada no redesign de 2026-08-10 é preservada — este trabalho apenas reveste.

## 5. Preferências

### Problemas específicos desta tela

1. `GeneralPane` é um `VStack` com títulos em negrito simulando seções. O macOS 13 já
   tem `Form` + `.formStyle(.grouped)`, o idioma nativo de Ajustes.
2. O campo "Saldo baixo (USD)" tem **botão Salvar** — estranho em Ajustes do macOS.
3. Pins são reordenados por setinhas ▲▼ em vez de arrastar.
4. `sidebarRow` está duplicado entre `PreferencesView` e `MainWindowView`.
5. Os dez painéis de provider montam cabeçalho e botões cada um do seu jeito.
6. Janela fixa em 640×460, não redimensionável.

### Estrutura nova

Todos os panes passam a usar `Form`/`.formStyle(.grouped)`, com o cabeçalho usando os
tokens do tema.

**Pane Geral**, três seções:
- *Barra de menu* — `List` com `.onMove` (arrastar para reordenar); as setinhas somem.
- *Alertas* — toggle mestre; limiares como chips selecionáveis; saldo baixo com
  auto-save.
- *Atualizações* — o aviso de nova versão, hoje só um badge no popover, ganha lugar fixo.

**Painéis de provider:** um `ProviderPaneScaffold` único — cabeçalho (ícone, nome, pill
de status, badge de plano), seção *Conexão* com a ação primária, seção *Detalhes*. Os dez
panes preenchem o scaffold em vez de montar layout próprio.

**Sidebar:** `ProviderSidebarRow` compartilhado com `MainWindowView`, eliminando a
duplicação. A seção "Contas" exibe quantas precisam de atenção.

**Janela:** redimensionável, mínimo 680×520.

### Decisões de comportamento (aprovadas pelo dono)

- **Auto-save em todos os campos**, incluindo chaves de API: commit em `onSubmit` e ao
  perder o foco. Os botões "Salvar" são removidos. Feedback passa a ser um selo
  "Salvo" transitório em vez do `statusMessage` no rodapé.
- **Limiares de alerta passam a 50/70/80/90/100 %.** *Nenhuma migração é necessária*:
  `PreferencesStore.alertPercentThresholds` já persiste uma lista arbitrária de frações
  (string separada por vírgula) e `AlertEngine.defaultThresholds` mapeia qualquer lista
  recebida. Quem já tem 70/90/100 salvo permanece com 70/90/100; o default para quem
  nunca tocou continua `[0.7, 0.9, 1.0]`.

## 6. Testes e verificação

- Lógica pura nova ganha testes unitários: construção das séries por janela (30/90/365),
  cálculo de delta hoje-vs-ontem, e a matemática de célula do heatmap responsivo
  (largura → tamanho de célula e número de semanas).
- `Tests/OkTallyTests/ReadmeAssetRenderer.swift` é estendido para exportar PNG de cada
  tela redesenhada — Análise, Visão geral, popover e os panes de Preferências (Geral e um
  pane de provider representativo); as imagens são inspecionadas a cada iteração antes da
  entrega.
- O auto-save ganha teste: alterar o valor e disparar o commit persiste em
  `PreferencesStore`; campo vazio não apaga a credencial existente.
- Ao final: `Scripts/build_app.sh`, instalação em `/Applications` e relançamento.

## Riscos

- **Swift Charts no macOS 13** não tem `chartScrollableAxes` nem `chartXVisibleDomain`
  (macOS 14+). Uso protegido por `if #available(macOS 14, *)`, com janela fixa no 13.
- **`ImageRenderer` não captura `ScrollView`.** Os PNGs renderizam o conteúdo
  diretamente, como o harness já faz com `PopoverContentView`.
- **Densidade do popover:** 360 pt é apertado para gráficos. Se a faixa "hoje" espremer
  os cards de cota, ela é cortada — a cota tem prioridade.
- **Auto-save de chave de API:** salvar a cada blur pode gravar uma chave colada pela
  metade. Mitigação: só grava quando o valor mudou e não está vazio, e o selo "Salvo"
  confirma visualmente; a chave antiga nunca é apagada por um campo vazio.

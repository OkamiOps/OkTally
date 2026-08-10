# OkTally — Redesign da interface + persistência MiMo (2026-08-10)

Aprovado pelo dono em 2026-08-10 (barra: vários pins compactos; Preferências: sidebar;
dropdown: repensar com cards/gauges; requisito extra explícito: **MiMo não pode exigir
relogin frequente**).

## Problemas que motivam o trabalho

1. A barra de menu é monocromática: `MenuBarExtra` ignora `foregroundStyle` no label
   (limitação do macOS, já prevista como risco na memória do projeto). O dono nunca sabe
   se está perto do limite sem abrir o dropdown.
2. Só uma janela de quota pode ser fixada na barra (`AppModel.menuBarPin` singular).
3. O MiMo "perde a configuração toda hora": o cookie STS da sessão web expira, o fetch
   devolve 401 e `MiMoUsageProvider` marca a sessão como deslogada na primeira falha,
   exigindo relogin manual — mesmo com o SSO da Xiaomi ainda válido no cookie store.
4. A tela de Preferências é um scroll único de cards sem hierarquia; o dropdown tem
   hierarquia fraca e não destaca o que está prestes a estourar.
5. Rebuilds invalidam o Keychain (assinatura ad-hoc muda o CDHash a cada build), gerando
   relogins de Claude/Codex/SuperGrok após cada atualização do app.

## 1. Barra de menu colorida com N pins

- `AppModel.menuBarPin: MenuBarPin?` vira `menuBarPins: [MenuBarPin]` (ordenada,
  persistida em UserDefaults; migração automática do valor singular antigo).
- `togglePin` adiciona/remove da lista, preservando a ordem de fixação.
- Novo `MenuBarLabelModel` (puro, testável): recebe snapshots + pins e produz uma lista
  de segmentos `[(glyph, glyphColor, valueText, valueColor)]`:
  - Pin com janela percentual → glifo do provider (cor de identidade de
    `ProviderPalette`) + `%restante` inteiro na cor de perigo de `QuotaPresentation`
    (verde >30 %, âmbar ≤30 %, vermelho ≤10 %). Ex.: `C 78 · X 86 · Cu 26`.
  - Pin com saldo (creditBalance/meteredOnly) → glifo + valor compacto (`19.8$`).
  - Pin cujo snapshot/janela sumiu → segmento omitido (sem placeholder).
  - Nenhum pin (modo automático) → segmento único: pior janela de todas, sem glifo,
    com `!` cinza quando só há erros e `OK` quando não há dados.
- Novo `MenuBarLabelRenderer`: desenha os segmentos num view SwiftUI e converte para
  `NSImage` **não-template** via `ImageRenderer` (escala 2x, altura ~16 pt) — é o único
  jeito de cor sobreviver na barra. O label do `MenuBarExtra` passa a ser
  `Image(nsImage:)`, recalculado quando snapshots ou pins mudam.
- `MenuBarStateCalculator` é absorvido pelo `MenuBarLabelModel` (o fallback automático
  reusa a mesma lógica de pior janela).

## 2. Dropdown (popover) com cards e gauges

Estrutura, de cima para baixo:

- **Header**: "OkTally" + resumo dos pins ("Barra: 3 fixados" / "Barra: automático").
- **Hero**: a janela mais crítica entre todas (menor fração restante; desempate: reset
  mais próximo). Anel de progresso grande (~56 pt) na cor de perigo, nome do provider +
  janela, "% restante" em destaque e countdown de reset. Some quando não há janelas.
- **Grade de cards 2 colunas**: um card por provider *com dados*. Card: chip colorido +
  nome, anel médio (~40 pt) da pior janela do provider, e abaixo uma linha compacta por
  janela (label, % ou valor, alfinete de pin). Cursor/OpenRouter (saldo) mostram o valor
  no lugar do anel percentual.
- **Rodapé de problemas**: providers sem dados agrupados em linhas discretas — cinza
  "não configurado", âmbar "reconectar" (com botão que abre Preferências), vermelho erro
  real (mensagem truncada, tooltip com o texto completo).
- **Footer**: Atualizar · Preferências · Sair (como hoje).
- Largura fixa 360 pt; altura máxima ~520 pt com scroll só na região de cards.

## 3. Preferências com sidebar

- `NavigationSplitView` (janela ~640×460): sidebar com seção **Geral** e a lista dos 8
  providers; cada linha tem chip colorido do provider + bolinha de status (verde
  conectado/chave salva, âmbar precisa reautenticar, cinza não configurado).
- Painel por provider: cabeçalho (chip grande, nome, status por extenso) + o corpo que
  cada um já tem hoje (login OAuth, campo de API key com Salvar, região do MiniMax,
  estimativa manual do MiMo, aviso do Cursor). Mensagens de status locais ao painel.
- Painel **Geral**: lista dos pins da barra (reordenar por arrastar, remover) e os
  intervalos de refresh por provider (`PreferencesStore.refreshInterval`), hoje sem UI.
- O status da sidebar deriva de `tokenStore`/`preferencesStore`/`mimoSessionStore` — a
  mesma fonte que os painéis já usam.

## 4. Persistência do MiMo (requisito central)

- `MiMoWebSession.fetchUsageJSON()` ganha recuperação: se a resposta contém
  `"code":401`, **recarrega a página do console** (`ensureConsoleLoaded(force: true)`,
  que re-roda a cadeia SSO → STS novo) e refaz o fetch. Só devolve 401 ao provider se o
  fetch pós-reload continuar 401 — ou seja, o SSO da Xiaomi realmente expirou.
- O loop de retry atual (6×2 s) é substituído por: fetch → (401?) reload+fetch →
  (401?) erro `notLoggedIn`. Menos espera cega, recuperação determinística.
- `MiMoUsageProvider` continua limpando `isLoggedIn` apenas ao receber
  `MiMoConsoleError.notLoggedIn` — que agora significa "SSO morto de verdade".
- O cookie store já é persistente (`WKWebsiteDataStore.default()`); a sessão web
  continua sobrevivendo a restarts do app. Nada muda na UI de login.

## 5. Assinatura estável (fim dos relogins pós-rebuild)

- `Scripts/build_app.sh`: se existir uma identidade de codesign chamada `OkTally Dev`
  no Keychain, assina com ela; senão mantém ad-hoc e imprime um aviso com o comando
  para criá-la (uma vez). Com identidade estável, o requirement do Keychain para de
  mudar a cada build e os tokens sobrevivem a atualizações.

## Fora de escopo

- Novos providers, mudanças de fetch/schema (além do retry do MiMo), thresholds de
  alerta configuráveis, histórico/sparklines.

## Testes

- `MenuBarLabelModel`: segmentos por tipo de shape, cores de perigo, omissão de pin
  órfão, fallback automático, migração pin singular → lista.
- `MiMoWebSession`/`MiMoUsageProvider`: 401 → reload → sucesso mantém `isLoggedIn`;
  401 → reload → 401 limpa e cai no manual (fetcher fake; sem WebKit real nos testes).
- UI (popover/preferências) permanece fora dos testes unitários, como hoje; validação
  visual manual via build local.

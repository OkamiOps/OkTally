# Task 12 — Scaffold dos painéis de provider

## O que mudou

**Novo: `Sources/OkTally/UI/ProviderPaneScaffold.swift`**

- `enum ProviderPaneStatus` (`connected` / `needsAttention` / `notConfigured`) com `text` e `tint`.
- `struct ProviderPaneScaffold<Connection, Details>` — `Form` agrupado com três seções: cabeçalho
  (chip de identidade + nome + pill de status), `Conexão` e detalhes.
- `struct AutoSaveField` — campo (texto ou `SecureField`) que chama `onCommit` no Enter **e** ao
  perder o foco, com `@FocusState` próprio. `.labelsHidden()` porque dentro de `Form` o título do
  campo vira rótulo visível e apareceria duplicado ao lado do placeholder (mesmo problema já
  corrigido no campo de saldo baixo da Task 11).

**`Sources/OkTally/UI/PreferencesView.swift`**

- Os dez painéis passam pelo scaffold: `claudePane`, `codexPane`, `superGrokPane`, `cursorPane`,
  `copilotPane`, `antigravityPane`, `keyPane` (openrouter/opencode), `minimaxPane`, `mimoPane`.
- `paneHeader(_:status:active:)` removido.
- O detalhe do `NavigationSplitView` não embrulha mais os painéis de provider num `ScrollView`:
  o `Form` agrupado rola sozinho e o par daria rolagem aninhada. O `statusMessage` saiu de dentro
  do scroll e ficou como rodapé do detalhe.
- Todos os botões "Salvar" saíram. Auto-save em: chave OpenRouter, chave OpenCode, chave MiniMax,
  região MiniMax (`onChange` do toggle), franquia e usados do MiMo.
- `saveSecret` reescrito com guarda `FieldCommit.sanitized` e novos helpers `saveMinimaxKey`,
  `saveMiMoAllowance`, `saveMiMoUsed`, `formatCredits`.

**`Sources/OkTally/Core/FieldCommit.swift`** — acrescentado `amount(_:)`: quantidade **não
negativa**, aceita vírgula decimal, recusa notação científica. `lowBalance` passou a ser
`amount` + `> 0`, então continua recusando zero. Motivo: "usados = 0" do MiMo é legítimo e
`lowBalance` o recusaria, mas eu não queria um parser duplicado solto na view.

**`Tests/OkTallyTests/FieldCommitTests.swift`** — teste novo para `amount` (aceita `0` e `40,5`,
recusa `-1`, `abc`, vazio e `1e3`).

**`Sources/OkTally/Resources/en.lproj/Localizable.strings`** — cinco chaves novas:
`Conexão`, `Estatísticas de uso vêm da API da conta.`,
`O uso de cota vem da conta; o volume em tokens é estimado dos transcritos locais.`,
`A chave fica no Keychain desta máquina, nunca em disco.`,
`O login usa código de dispositivo: o navegador abre e você digita o código mostrado aqui.`
Todas as demais strings dos painéis já existiam e foram reaproveitadas literalmente.

## Trace de segurança de cada campo com auto-save

A regra: **campo vazio nunca apaga credencial salva; valor inalterado não gera escrita.**
Cenário testado mentalmente em todos: *usuário seleciona tudo, apaga sem querer e clica fora.*

| Campo | Caminho de gravação | Campo vazio + blur | Inalterado + blur |
|---|---|---|---|
| OpenRouter API key | `saveSecret("OpenRouter", previous: preferencesStore.openRouterAPIKey ?? "", raw: $openRouterAPIKey)` | `FieldCommit.sanitized` → `nil` → **return antes de `setOpenRouterAPIKey`**; o campo volta ao valor salvo | `nil` → nenhuma escrita no Keychain |
| OpenCode API key | idem com `openCodeAPIKey` | idem | idem |
| MiniMax API key | `saveMinimaxKey` → mesmo `saveSecret` | idem | idem |
| MiniMax região | `onChange(of: minimaxRegionIsChina)` | não se aplica — toggle binário, não existe estado vazio | `onChange` só dispara quando muda |
| MiMo franquia | `saveMiMoAllowance` | `sanitized` → `nil` → **return antes de tocar em `mimoMonthlyAllowanceCredits`**; campo volta ao salvo | `nil` → nada |
| MiMo usados | `saveMiMoUsed` | idem, com `FieldCommit.amount` no lugar de `lowBalance` para aceitar `0` | idem |

O alerta herdado da revisão anterior está fechado: a linha
`preferencesStore.mimoMonthlyAllowanceCredits = Double(mimoAllowance)` não existe mais. Com o
campo vazio ela gravava `nil` e apagava a franquia; hoje o `guard let candidate =
FieldCommit.sanitized(...)` sai antes da atribuição e restaura o texto salvo.

Detalhe que sustenta o "inalterado não escreve": `load()` e os três commits renderizam o número
pelo mesmo `formatCredits` (`String(Double)`). Se divergissem, `previous` nunca bateria com o
texto e todo blur gravaria de novo.

Duas escolhas conscientes:

1. `saveSecret` agora persiste o valor **saneado** (`try save(value)`), não o texto cru — a chave
   vai para o Keychain sem espaços colados de um paste.
2. Quando o commit é recusado, o campo volta ao valor salvo em vez de ficar vazio. Sem isso o
   usuário veria um campo em branco e concluiria que a credencial sumiu.

## Preservação dos fluxos

Nenhum fluxo de login mudou de comportamento — só a casca:

- **Claude**: Entrar / Importar do Claude Code / Sair e a sessão de código colado (campo
  `CÓDIGO#STATE`, Concluir, Cancelar) continuam na seção `Conexão`. Deliberadamente **não** mandei
  o código colado para `details`: ele é um passo do login e ficaria descolado dos botões.
- **Codex**: `login(config: CodexOAuth.config, flag:)` / `logout` intactos.
- **SuperGrok**: `loginSuperGrok()` intacto; o bloco do device code foi para `details` conforme o
  brief, com um texto explicativo quando não há código em andamento (a seção ficaria vazia).
- **Cursor / Copilot / Antigravity**: continuam sem ação de conexão; o status vem dos mesmos
  `CopilotTokenReader().firstToken()` e `AntigravityTokenReader().readTokens()`.
- **MiMo**: `MiMoWebSession.shared.presentLogin` e a remoção de sessão intactos.

## Comandos e saída

```
$ swift build 2>&1 | tail -3
Building for debugging...
[0/3] Write swift-version--58304C5D6DBC2206.txt
Build complete! (0.30s)

$ swift test 2>&1 | grep -E "Executed .* tests, with"
	 Executed 280 tests, with 1 test skipped and 0 failures (0 unexpected) in 0.868 (0.918) seconds

$ ./Scripts/build_app.sh 2>&1 | tail -3
Signed with stable identity 'Apple Development'.
Built .build/OkTally.app
```

(O 1 teste pulado é o `ReadmeAssetRenderer`, que só roda com `RENDER_README_ASSETS=1`.)

## Verificação visual

O passo 8 do brief **falhou como previsto**: acrescentei a renderização do scaffold ao
`ReadmeAssetRenderer`, rodei `RENDER_README_ASSETS=1 swift test --filter ReadmeAssetRenderer`,
abri `docs/assets/preferences-provider.png` — e o PNG saiu **inteiramente em branco**, porque o
`ImageRenderer` não desenha `Form` agrupado (o mesmo motivo pelo qual o pane Geral nunca foi
renderizado nesses assets). Removi a chamada, apaguei o PNG em branco e deixei um comentário no
`ReadmeAssetRenderer` explicando por quê, para ninguém tentar de novo. Os outros quatro assets
foram re-renderizados idênticos (nenhum diff no `git status`).

No lugar disso renderizei o scaffold com `NSHostingView` + `cacheDisplay(in:to:)`, que desenha
controles do AppKit de verdade, num arquivo de teste temporário (`ScratchPaneRender.swift`,
apagado depois — não está no commit). Duas imagens, ambas olhadas:

1. Scaffold com botão "Sair": chip verde-azulado com o glifo `X`, "Codex" em bold, pill verde
   "Conectado", seção "Connection" com o botão dentro de um cartão, cartão de detalhe com a
   legenda. Layout correto.
2. Mesmo scaffold com `AutoSaveField` seguro (bolinhas, largura 380) e o par franquia/usados do
   MiMo lado a lado dentro do cartão de detalhes. Sem rótulo duplicado, sem campo esticado
   errado, sem corte.

O `.app` foi construído com `Scripts/build_app.sh` e assinado sem erro. **Não** cliquei pela tela
de Preferências no app rodando: OkTally é app de barra de menu e a sessão não é interativa, então
o `request_access` do computer-use não teria como ser aprovado. Prefiro dizer isso a inventar que
abri.

## Alturas fixas

Nenhuma. O único `frame` com números no scaffold é o `40×40` do chip de identidade, que já existia
no `paneHeader` removido e é um ícone, não um contêiner de conteúdo. `frame(maxWidth: 380/420)`
nos campos são larguras máximas, não alturas.

## Riscos e pendências

1. **Não há mais como esvaziar a franquia do MiMo pela UI.** É a consequência direta da regra do
   dono ("campo vazio nunca apaga"). Se algum dia for preciso zerar, precisa de um gesto explícito
   (um botão "Limpar"), não de um campo em branco.
2. **Sem feedback visível quando o commit é recusado.** O campo volta ao valor salvo e nada é dito.
   As chaves de API dizem "salvo" quando dá certo, mas o silêncio no caso recusado pode confundir
   quem apagou de propósito. O pane Geral tem um flash "Salvo" que poderia ser generalizado.
3. **`previous` das chaves lê o Keychain a cada commit** (`preferencesStore.minimaxAPIKey` etc.).
   É uma leitura por blur, custo irrelevante, mas é uma ida ao Keychain que antes não acontecia.
4. **O `ImageRenderer` continua cego para `Form` agrupado.** Qualquer task futura que queira um
   PNG das Preferências vai bater no mesmo muro — o caminho que funciona é `NSHostingView` +
   `cacheDisplay`.

---

# Fix round 1

Três achados Importantes da revisão, mais os menores. Tudo corrigido.

## Importante 1 — caminho explícito de revogação

A regra do dono ("campo vazio não apaga") **não** foi afrouxada. O que faltava era o gesto
deliberado, e ele agora existe: botão **"Remover chave"** (`role: .destructive`) na seção
`Conexão` dos três painéis com chave — OpenRouter, OpenCode e MiniMax. Aparece só quando há chave
(`if !text.wrappedValue.isEmpty`) e chama o caminho de exclusão real,
`preferencesStore.set*APIKey(nil)` → `setSecret(nil, …)` → `secretStore.delete(providerId:)`.

`keyPane` ganhou o parâmetro `remove:` e o `minimaxPane` tem o botão embutido. O efeito colateral
vive em `removeSecret(_:raw:_:)`, separado de `saveSecret` de propósito: só ele apaga, e só por
clique.

Ordem de eventos conferida: clicar em "Remover" tira o foco do `SecureField` primeiro, então o
`onCommit` do blur roda antes — com texto inalterado, `sanitized` devolve `nil`, nada é gravado, e
só então a exclusão acontece. E depois de remover, `previous` passa a ser `""`, então nenhum commit
posterior ressuscita a chave.

## Importante 2 — a composição agora tem teste

Extraí a lógica para `Sources/OkTally/Core/PreferencesFieldCommit.swift`, fora da View:

- `enum FieldCommitOutcome<Value>` — `.ignored(restore:)` ou `.commit(value:display:)`.
- `PreferencesFieldCommit.secret(raw:saved:)`, `.allowance(raw:saved:)`, `.used(raw:saved:)` e
  `.credits(_:)`.

São funções puras: a decisão inteira (gravar ou ignorar, qual parser, para que texto o campo volta)
saiu da View; em `PreferencesView` sobraram só os efeitos colaterais — escrever no Keychain,
escrever no `UserDefaults`, mexer no `@State`. `formatCredits` foi substituído por
`PreferencesFieldCommit.credits`, usado tanto no `load()` quanto nos commits.

`Tests/OkTallyTests/PreferencesFieldCommitTests.swift`, 12 testes novos, sem Keychain nenhum:

- chave: vazio e só-espaços não apagam a chave salva; inalterado não regrava; chave nova é gravada
  saneada (sem espaços de paste); vazio sem chave salva continua vazio;
- franquia: vazio, `abc`, `1e3`, `inf` e `0` → `.ignored(restore: "500.0")`, ou seja, o valor salvo
  sobrevive; `750,5` → `.commit(750.5, "750.5")`; e um teste de ida-e-volta que prova que o
  `display` de um commit é reconhecido como "inalterado" no commit seguinte (é o que impede o blur
  de regravar sem parar);
- usados: vazio não apaga; `0` é aceito (`.commit(0, "0.0")`); negativo, `inf`, `nan` e lixo são
  recusados sem destruir o salvo.

**Prova de que os testes mordem** (mutation check): troquei o corpo de `secret` por um
`trimmingCharacters` sem guarda e o de `allowance` por `Double(raw) ?? 0` →
`Executed 12 tests, with 13 failures`. Restaurado → `Executed 12 tests, with 0 failures`.

Suíte inteira: 292 testes (eram 280), 1 pulado, 0 falhas.

## Importante 3 — edição perdida ao trocar de painel

`AutoSaveField` ganhou `.onDisappear(perform: onCommit)`. Digitar a chave e clicar direto no
próximo provedor da sidebar agora grava. É seguro repetir o commit porque `sanitized` recusa vazio
e inalterado — no pior caso o `onDisappear` roda depois do blur e não faz nada.

## Menores

- `FieldCommit.amount` ganhou `value.isFinite`: `amount("inf")` devolvia `+∞` e gravaria infinito
  em `mimoUsedCredits`. `lowBalance` herda a correção por ser `amount` + `> 0`. Testes novos em
  `FieldCommitTests` para `inf`, `-inf`, `nan` e `lowBalance("inf")`.
- Comentário obsoleto (`PreferencesView.swift:153`): "tratado antes do `ScrollView`" →
  "tratado no branch anterior do detalhe, por rolar sozinho".
- Texto honesto: `"A chave fica no Keychain desta máquina, nunca em disco."` →
  `"A chave fica no Keychain desta máquina, nunca em texto puro."` (o Keychain *é* disco). Chave
  antiga removida do `Localizable.strings`, nova acrescentada, e as duas ocorrências no Swift
  atualizadas. Três chaves novas para a revogação: `Remover chave`, `%@: chave removida.`,
  `%@: falha ao remover chave — %@`.

## Verificação visual desta rodada

Renderizei de novo com `NSHostingView` + `cacheDisplay` (arquivo temporário, apagado) o painel de
chave com a chave preenchida: pill verde "Chave salva", `SecureField` mascarado e o botão
"Remover chave" logo abaixo, dentro do mesmo cartão da seção Conexão, e o rodapé com o texto novo.
Olhei o PNG. `swift build`, `swift test` e `Scripts/build_app.sh` verdes.

## Para a triagem final

- **`Section` vazio nos painéis de detecção automática** (Cursor, Copilot, Antigravity): o
  `details:` deles é `EmptyView()`, e o `Form` ainda desenha o `Section` — sai um cartão vazio no
  fim do painel. Deixado como está por pedido da revisão; anotado aqui.
- `ProviderPaneStatus.needsAttention` continua sem uso (veio do brief) — deixado como está.
- `"Salvar"` virou chave órfã no `Localizable.strings` agora que nenhum painel tem botão Salvar.
  Não removi: é genérica e outra task pode estar prestes a usá-la.
- Uma varredura programática das 183 chaves `L`/`LF` do app achou 3 ausentes no
  `Localizable.strings` — `"12 m"`, `"30 d"`, `"90 d"`, os rótulos de período da aba Análise.
  São de outra task, não desta; ficam registradas aqui.

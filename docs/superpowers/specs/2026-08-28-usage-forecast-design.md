# OkTally — previsão de esgotamento de cotas — 2026-08-28

Design aprovado pelo dono em 2026-08-28.

## Objetivo

Transformar o percentual atual de uma cota renovável em uma resposta acionável:

- mantendo o ritmo líquido das últimas 24 horas, quando a cota deve acabar;
- quando a assinatura renova;
- quanto tempo de falta ou folga existe entre os dois eventos;
- qual ritmo diário ainda é seguro até a renovação.

A previsão é sempre apresentada como **estimativa pelo ritmo das últimas 24h**, nunca
como certeza. O produto deve ajudar o dono a decidir se precisa desacelerar ou se ainda
pode acelerar.

## Decisões aprovadas

- Interface compacta escolhida: **duas barras comparáveis**.
- Superfícies: um card no popover e um gráfico completo no detalhe do provider.
- O escopo não é limitado a semanal: inclui cotas de assinatura com renovação
  **semanal ou mensal**.
- O alvo da previsão é independente do herói do popover:
  - automático, escolhendo a cota renovável de maior risco;
  - manual, escolhendo uma janela específica nas Preferências.
- O ritmo é a **variação líquida observada nas últimas 24 horas**.
- Alertas/notificações preditivas ficam fora da primeira versão.
- Não haverá gráfico agregado na tela Overview geral nesta primeira versão.

## 1. Modelo de dados

### `RenewalCadence`

Novo enum persistível:

```swift
enum RenewalCadence: String, Codable, Equatable {
    case weekly
    case monthly
}
```

`QuotaWindow` ganha `renewalCadence: RenewalCadence?`, com valor padrão `nil` no
initializer e decode retrocompatível. Snapshots antigos continuam válidos e apenas não
participam da previsão até uma leitura nova do provider ser persistida.

Os providers marcam explicitamente somente as janelas renováveis reais:

- Claude: semanal e Opus semanal;
- Codex: janelas que o contrato identifica como semanais;
- Cursor: percentual do ciclo mensal;
- SuperGrok: semanal;
- GrokBot: semanal;
- MiniMax: semanal;
- Antigravity: grupos semanais;
- MiMo: mensal quando houver percentual e reset reais.

Janelas de 5 horas, saldos em dinheiro, medição sem limite e shapes sem `resetAt` não
são elegíveis. `QuotaShape.estimated` fica fora da primeira versão para evitar uma
previsão construída sobre outra estimativa.

### Identidade da janela

A série é identificada por `providerId + window.label`. Uma amostra só pertence ao
ciclo atual quando seu `resetAt` coincide com o reset atual, admitindo tolerância de
60 segundos para pequenas diferenças de serialização.

## 2. Engine de previsão

Novo `UsageForecastEngine`, puro e sem dependência de SwiftUI ou SQLite.

### Entrada

- janela atual;
- snapshots do mesmo provider nas últimas 24 horas;
- `now` injetável;
- provider/window alvo.

### Preparação da série

1. Selecionar a janela exata em cada snapshot.
2. Manter somente shapes percentuais e o mesmo `resetAt` do ciclo atual.
3. Ordenar por `fetchedAt`.
4. Descartar amostras futuras e anteriores a `now - 24h`.
5. Manter amostras repetidas: períodos sem consumo fazem parte do ritmo real.

### Critério mínimo

A previsão numérica só existe quando a série possui:

- pelo menos 3 horas entre a primeira e a última amostra;
- pelo menos 6 amostras;
- aumento líquido mínimo de 0,5 ponto percentual.

Antes disso o resultado é `collecting`, com o tempo observado e a quantidade de
amostras disponíveis. Não se inventa data de esgotamento.

### Fórmulas

Valores percentuais são expressos em pontos percentuais, e tempo em horas:

```text
observedHours = latest.date - earliest.date
consumed = max(0, latest.usedPercent - earliest.usedPercent)
ratePerHour = consumed / observedHours
remaining = max(0, 100 - latest.usedPercent)
hoursToReset = current.resetAt - now
safeRatePerHour = remaining / hoursToReset
exhaustionAt = now + remaining / ratePerHour
gap = resetAt - exhaustionAt
```

`gap > 0` significa que a cota acaba antes da renovação. `gap < 0` significa folga.

Uma queda líquida no percentual é tratada como correção do provider, não como consumo
negativo: o ritmo fica zero e nenhuma data de esgotamento é produzida até a série voltar
a acumular pelo menos 0,5 ponto.

### Estado de ritmo

Uma tolerância de 6 horas evita que pequenas oscilações troquem o texto a cada poll:

- `slowDown`: esgotamento mais de 6h antes da renovação;
- `onPace`: esgotamento dentro de ±6h da renovação;
- `canAccelerate`: esgotamento mais de 6h depois da renovação;
- `noExhaustion`: ritmo zero ou pequeno demais para produzir data;
- `collecting`: histórico insuficiente;
- `unavailable`: janela não elegível, reset ausente/expirado ou série inválida.

O resultado inclui `ratePerDay`, `safeRatePerDay`, `exhaustionAt`, `resetAt`, `gap` e o
estado. A UI não recalcula matemática.

## 3. Seleção da previsão

### `ForecastSlot`

Nova preferência, separada de `popoverHeroSlot`:

- `.automatic`;
- `.window(providerId:windowLabel:)`.

É persistida no `PreferencesStore` e publicada pelo `AppModel`. O seletor lista todas
as janelas elegíveis presentes nos snapshots atuais, independentemente dos pinos da
barra de menu.

### Modo automático

1. Calcular previsões para todas as janelas elegíveis.
2. Se alguma acaba antes da renovação, escolher a de maior `gap` positivo — a maior
   falta projetada.
3. Se todas chegam até a renovação, escolher a de menor folga absoluta.
4. Se nenhuma tem histórico suficiente, escolher a janela elegível com maior intervalo
   observado e mostrar `collecting`.

Um alvo manual ausente não é apagado das preferências: a apresentação cai
silenciosamente para automático e volta ao alvo escolhido quando a janela reaparece.

## 4. Fluxo de dados

O SQLite existente continua sendo a única persistência de histórico; não há tabela ou
migração nova.

1. O Scheduler salva o novo `ProviderSnapshot` como já faz hoje.
2. Após uma leitura bem-sucedida, o `AppModel` agenda a recomputação das previsões do
   provider afetado fora da main thread.
3. O engine recebe `storage.snapshots(providerId:since:)` para as últimas 24h.
4. O resultado publicado alimenta o popover e o detalhe do provider.
5. No launch, snapshots persistidos aparecem imediatamente e as previsões são
   recalculadas em background.

O modelo mantém previsões por `QuotaSlot`/identidade de janela. Views apenas selecionam
e apresentam resultados prontos.

## 5. Popover — duas barras

Um único `ForecastBarsView` entra logo abaixo do herói e antes da faixa de analytics.
Altura compacta; não há gráfico nem legenda no popover.

Conteúdo:

```text
GB  GrokBot · Semanal                         73%

Desacelere · pode acabar 1d 12h antes
Seu ritmo      ━━━━━━━━━━━━━━━          2d 3h
Renovação      ━━━━━━━━━━━━━━━━━━━━━    3d 15h

Ritmo 24h: 14,2%/dia · Seguro: até 11,8%/dia
```

As barras usam a mesma escala temporal, de `now` até o evento mais distante entre
esgotamento e renovação:

- `Seu ritmo`: termina em `exhaustionAt`; cor semântica da escala do OkTally;
- `Renovação`: termina em `resetAt`; cor de identidade do provider.

Quando não há esgotamento previsto, a primeira barra é cheia e o texto diz que o ritmo
atual chega à renovação. No estado `collecting`, as barras são substituídas por uma
linha neutra de progresso de coleta, sem data falsa.

Textos:

- `slowDown`: “Desacelere · pode acabar %@ antes”;
- `onPace`: “No ritmo certo · chega perto da renovação”;
- `canAccelerate`: “Pode acelerar · chega com %@ de folga”;
- `noExhaustion`: “Pode acelerar · sem esgotamento previsto neste ritmo”;
- `collecting`: “Coletando ritmo · %@ de histórico”;
- `unavailable`: card omitido no modo automático; alvo manual mostra explicação neutra.

Não são criadas cores ou tipografias novas. O card usa o design system atual; a dupla
de barras é o elemento de assinatura desta feature.

## 6. Detalhe do provider — gráfico completo

`ForecastChartView` entra depois do herói do provider e antes da área de analytics.

Séries:

- histórico real das últimas 24h, em ciano;
- projeção a partir de agora até o esgotamento, tracejada e em cor semântica;
- ritmo seguro a partir do percentual atual até zero no reset, tracejado na cor do
  provider.

A linha segura começa em **agora**, não no início inferido do ciclo. Isso evita inventar
um ciclo inicial que `periodicCounter` não armazena.

O eixo X cobre as últimas 24h e avança até o evento mais distante entre reset e
esgotamento. O eixo Y é percentual restante, de 100% a 0%.

Abaixo do gráfico:

- data/hora prevista de esgotamento;
- data/hora da renovação;
- falta ou folga projetada;
- ritmo observado por dia;
- ritmo seguro por dia.

Quando o provider tem mais de uma janela elegível, um seletor local troca a janela do
gráfico sem alterar o alvo global do popover.

## 7. Preferências

Em **Preferências → Geral → Barra de menu**, depois de “Destaque do menu”:

- seletor “Previsão de consumo”;
- opção “Automático — maior risco”;
- uma opção por janela semanal/mensal elegível;
- rodapé curto explicando que a previsão usa a variação líquida das últimas 24h.

O seletor não depende dos pinos da barra e não muda o herói.

## 8. Tratamento de incerteza e falhas

- Nenhuma previsão aparece como certeza; a UI usa “pode acabar” e “estimativa 24h”.
- Falha de SQLite ou decode mantém a última previsão publicada e não vira erro do
  provider.
- Reset ausente, passado ou divergente produz `unavailable`, não zero nem data atual.
- Mudança de `resetAt` inicia ciclo novo automaticamente.
- Um poll isolado sem mudança não altera o estado de forma abrupta, porque o ritmo usa
  a janela inteira observada.
- Percentual acima de 100 é limitado para apresentação; o valor bruto continua no
  snapshot.
- Datas são apresentadas no locale do sistema.

## 9. Performance

- Recomputar apenas o provider atualizado.
- Consultar no máximo 24h de snapshots.
- Engine linear no número de amostras.
- Cálculo e leitura de SQLite fora da main thread.
- Views não iniciam queries durante `body`.

## 10. Testes e validação

### Engine

- acaba antes, dentro da tolerância e depois da renovação;
- ritmo zero;
- menos de 3h, menos de 6 amostras e menos de 0,5 ponto;
- mudança de ciclo/reset;
- correção negativa do percentual;
- amostras repetidas e fora de ordem;
- reset ausente ou passado;
- limite em 100% e percentual acima de 100.

### Elegibilidade e seleção

- semanal e mensal elegíveis;
- 5h, saldo, metered e estimated inelegíveis;
- automático escolhe maior falta;
- automático escolhe menor folga quando todos estão seguros;
- manual escolhe Claude semanal e Cursor mensal;
- alvo manual ausente cai para automático sem apagar a preferência;
- round-trip da preferência.

### UI

- textos de todos os estados em português e inglês;
- duas barras compartilham a mesma escala temporal;
- popover compacto em 360pt;
- detalhe em largura normal e estreita;
- render offscreen escuro e claro via `NSWindow + NSHostingView + cacheDisplay`;
- nenhuma previsão para janela de 5h;
- seletor local não altera a preferência global.

### Integração real

- `swift test` completo;
- build assinada por `Scripts/build_app.sh`;
- app instalado em `/Applications/OkTally.app`;
- processo executando a build nova;
- snapshot real com histórico suficiente produz barras e gráfico;
- mudança de alvo em Preferências atualiza o popover sem relaunch.

## Fora de escopo

- machine learning, sazonalidade por dia da semana ou modelo adaptativo;
- alertas/notificações preditivas;
- gráfico agregado no Overview geral;
- previsões para janelas de 5h;
- previsão sobre `QuotaShape.estimated`;
- alteração do período de retenção de 30 dias;
- sincronização ou servidor remoto.

## Critérios de aceite

1. O dono consegue fixar Claude semanal ou Cursor mensal como previsão do popover.
2. O modo automático mostra a cota renovável com maior risco projetado.
3. O popover responde, com duas barras, se a cota acaba antes ou depois da renovação.
4. O detalhe do provider mostra histórico, ritmo seguro e projeção na mesma escala.
5. Histórico insuficiente nunca produz uma data inventada.
6. Janelas de 5h não entram na previsão.
7. O cálculo é reproduzível e testável com `now` injetável.
8. A feature não bloqueia refresh, render ou interação na main thread.

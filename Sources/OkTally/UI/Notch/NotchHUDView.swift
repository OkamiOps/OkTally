// Sources/OkTally/UI/Notch/NotchHUDView.swift
import SwiftUI

/// Paleta do painel do notch. Preto SÓLIDO, sem vidro e sem `Theme.pageBackground`.
///
/// O notch físico é preto opaco; o painel só passa por extensão dele se compartilhar
/// exatamente esse preto. Vidro aqui denunciaria a emenda na primeira janela clara que
/// passasse por baixo — e o dono pediu explicitamente "zero vidro" neste lugar. Pelo
/// mesmo motivo nada aqui usa `.primary`/`.secondary`: o painel é sempre escuro,
/// independentemente do tema do sistema.
enum NotchPalette {
    static let ink = Theme.Brand.offWhite
    static let inkDim = Theme.Brand.offWhite.opacity(0.62)
    static let track = Color.white.opacity(0.14)
    /// Trilho da barra da borda: mais forte que o das listas de propósito. Num traço de
    /// 2,5pt sobre preto sólido, 0.14 de branco desaparece — e um trilho invisível
    /// devolve o problema que a barra veio resolver.
    static let ruleTrack = Color.white.opacity(0.22)
}

// MARK: - Fechado

/// O que abraça o notch quando o painel está discreto: UMA cota escolhida de cada lado
/// do recorte, no estilo da Dynamic Island.
///
/// Antes daqui as duas asas eram a marca de um lado e uma fileira de tracinhos do outro —
/// bonito e mudo: os tracinhos diziam "tem cinco cotas e uma delas está baixa", nunca
/// *qual* nem *quanto*, e o dono não escolhia nada. O que ele pediu foi poder apontar um
/// valor para cada lado. Um chip de identidade mais um número cabem nos ~90pt de cada asa
/// e respondem as duas perguntas de uma vez.
///
/// Em automático a asa esquerda pega a cota mais apertada e a direita a seguinte (nunca a
/// mesma) — ver `QuotaSlotResolver.wings`.
struct NotchCompactLeading: View {
    /// Observa o modelo em vez de receber o valor pronto: `DynamicNotch` guarda o
    /// conteúdo UMA vez, na criação do painel, então um valor passado por cópia
    /// congelaria no número do momento em que o app subiu.
    @ObservedObject var appModel: AppModel
    @ObservedObject private var span = NotchBarSpan.shared

    var body: some View {
        NotchWing(segment: appModel.notchWings.leading, showsBrandFallback: true)
            .measuringNotchSpan(\.leading)
            // A asa esquerda é quem desenha a barra INTEIRA — ver `NotchBottomRule`.
            .overlay(alignment: .bottomLeading) {
                NotchBottomRule(bar: appModel.notchBottomBar, totalWidth: span.width)
                    // Alinhada pelo fundo do chip e EMPURRADA para dentro do respiro que
                    // o pacote reserva embaixo — sem o deslocamento a barra sublinharia o
                    // chip, no meio do painel, em vez de correr pela borda de baixo dele.
                    .offset(y: NotchBottomRule.reservedBottomInset - NotchBottomRule.bottomGap)
            }
    }
}

struct NotchCompactTrailing: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        NotchWing(segment: appModel.notchWings.trailing, showsBrandFallback: false)
            // Não desenha barra nenhuma: só informa onde o painel TERMINA.
            .measuringNotchSpan(\.trailing)
    }
}

// MARK: - Barra inferior

/// Onde a barra contínua começa e onde ela termina, em coordenadas da janela.
///
/// O painel fechado chega até nós PARTIDO EM DOIS: `DynamicNotchKit` desenha a asa
/// esquerda e a direita como views irmãs, com o recorte entre elas, e nenhuma das duas
/// sabe onde a outra acaba. Uma barra de ponta a ponta precisa exatamente dessa medida —
/// daí esta caixinha compartilhada, onde cada asa publica o próprio retângulo. Um objeto
/// único (e não um valor injetado) porque existe UM painel de notch no app inteiro, e
/// porque as duas asas são criadas por closures independentes do controller: não há
/// ancestral nosso onde uma `PreferenceKey` pudesse se encontrar.
@MainActor
final class NotchBarSpan: ObservableObject {
    static let shared = NotchBarSpan()

    @Published var leading: CGRect = .zero
    @Published var trailing: CGRect = .zero

    /// Da ponta esquerda do painel até a direita. Zero enquanto ninguém mediu — e aí a
    /// barra simplesmente não é desenhada, em vez de aparecer com um comprimento chutado.
    var width: CGFloat { max(0, trailing.maxX - leading.minX) }
}

private extension View {
    /// Publica o retângulo desta asa na caixinha compartilhada, sem mexer no layout.
    func measuringNotchSpan(_ key: ReferenceWritableKeyPath<NotchBarSpan, CGRect>) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
            NotchBarSpan.shared[keyPath: key] = rect
        }
    }
}

/// A barra fina da borda inferior do notch fechado — um traço de 2,5pt com o quanto RESTA
/// da cota escolhida (`notchBottomSlot`; em automático, a mais apertada).
///
/// ## Uma barra só, de ponta a ponta
///
/// A primeira versão eram duas metades ancoradas no recorte, crescendo para fora. O dono
/// olhou e recusou: "eu queria uma barra contínua que fosse de um lado pro outro pra eu
/// ter noção do gasto, não uma pequena de cada lado". Ele tem razão — duas metades
/// espelhadas obrigam o olho a somar dois comprimentos para estimar um número só, que é
/// exatamente o trabalho que uma barra de progresso existe para poupar.
///
/// Então é UMA barra, preenchida da esquerda para a direita como qualquer barra de
/// progresso, correndo por baixo do recorte. Ela é desenhada inteira pela asa ESQUERDA,
/// num `overlay` mais largo que a própria asa: overlay não é recortado pelos limites de
/// quem o hospeda, e o painel inteiro já é mascarado pela `NotchShape` do pacote — o que
/// passar da borda é aparado por ela, não por nós.
///
/// Cheia = FOLGA, igual a `QuotaCapsuleBar` e a todo o resto do app: a barra esvazia
/// conforme o uso é consumido, que é o "quanto falta pra acabar" que foi pedido.
///
/// Cor pela escala de perigo (`QuotaPresentation.color(remaining:)`) e não pela
/// identidade do provedor: ela ACOMPANHA o valor caindo — ciano com folga, Heat Orange
/// apertando, Neon Magenta no crítico. Num traço de 2,5pt a cor não consegue fazer as
/// duas coisas, e quem é o provedor já está dito pelo chip logo acima.
///
/// No estado EXPANDIDO ela não existe: o `DynamicNotchKit` só desenha as asas em
/// `.compact`, e o painel aberto já traz uma `QuotaCapsuleBar` própria por linha.
struct NotchBottomRule: View {
    let bar: NotchBottomBar?
    /// Largura do painel fechado inteiro, medida pelas duas asas (`NotchBarSpan`).
    let totalWidth: CGFloat

    /// Traço, não layout: a espessura é a identidade visual do elemento, do mesmo jeito
    /// que a de um `Divider`. Abaixo de 2pt ela some no antialiasing da borda curva do
    /// painel; acima de 3pt deixa de ser "fininha" e vira uma segunda barra de progresso.
    private static let thickness: CGFloat = 2.5

    /// O respiro que o `DynamicNotchKit` reserva embaixo do conteúdo compacto
    /// (`NotchView.compactContent`, `safeAreaInset(edge: .bottom)` de 8pt). A barra mora
    /// DENTRO desse respiro: é o que a coloca na borda do painel sem empurrar o chip.
    static let reservedBottomInset: CGFloat = 8

    /// Distância da barra até a borda inferior do painel. Encostar de fato na borda a
    /// faria entrar na curva do canto, que a cortaria na ponta de fora.
    static let bottomGap: CGFloat = 3

    var body: some View {
        if let bar, totalWidth > 0 {
            ZStack(alignment: .leading) {
                // O trilho precisa ser VISÍVEL: sem ele não há proporção, e sem proporção
                // não dá para ver o quanto falta — só o quanto sobrou em pixels soltos.
                Capsule().fill(NotchPalette.ruleTrack)
                Capsule()
                    .fill(QuotaPresentation.color(remaining: bar.remaining))
                    .frame(width: max(Self.thickness,
                                      totalWidth * Theme.clampFraction(bar.remaining)))
                    .animation(.easeInOut(duration: 0.3), value: bar.remaining)
            }
            .frame(width: totalWidth, height: Self.thickness)
        }
    }
}

/// Uma asa: chip da marca do provedor + o quanto resta.
///
/// Chip e não tracinho: fechado, o painel divide a altura da barra de menu com o relógio
/// e os ícones do sistema, e a única coisa que sobrevive nesse tamanho é uma forma de cor
/// sólida com uma letra dentro. A cor do chip é a de IDENTIDADE do provedor — é ela que
/// diz de quem é o número sem gastar largura escrevendo o nome.
struct NotchWing: View {
    let segment: MenuBarSegment?
    /// Sem dado nenhum a asa esquerda vira a marca do app, e não um buraco preto: um
    /// painel vazio no notch é indistinguível de um painel quebrado.
    let showsBrandFallback: Bool

    var body: some View {
        if let segment {
            HStack(spacing: 5) {
                IconChip(glyph: segment.glyph ?? "?",
                         color: ProviderPalette.color(for: segment.providerId ?? ""),
                         size: 15)
                Text(segment.text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.color(for: segment.danger))
                    .lineLimit(1)
                    .fixedSize()
            }
        } else if showsBrandFallback {
            BrandMark(size: 13)
                .foregroundStyle(NotchPalette.ink)
        }
    }

    /// Número NEUTRO com folga, cor quando aperta — a mesma regra do resto do app
    /// (`QuotaPresentation.valueColor`), com o off-white do painel no lugar do `.primary`,
    /// que sobre preto sólido dependeria do tema do sistema. Um número permanentemente
    /// verde ensinaria o olho a ignorar a cor justo quando ela finalmente muda.
    private static func color(for danger: DangerLevel) -> Color {
        switch danger {
        case .ok, .neutral: return NotchPalette.ink
        case .warn: return Theme.Brand.heatOrange
        case .critical: return Theme.Brand.neonMagenta
        }
    }
}

// MARK: - Expandido

/// O painel aberto: uma linha densa por cota, no mesmo idioma do popover (chip de
/// identidade, barra do que resta, porcentagem, contagem para o reset).
///
/// Sem altura fixa em lugar nenhum: a lista tem de uma a cinco linhas e o `NSPanel` é
/// dimensionado pelo conteúdo, então qualquer altura cravada aqui cortaria linhas em uma
/// configuração e deixaria buraco preto em outra.
struct NotchExpandedView: View {
    @ObservedObject var appModel: AppModel
    /// Clique em qualquer parte do painel. Injetado pelo controller (que sabe abrir o
    /// popover); a view não conhece janela nenhuma.
    let onOpen: () -> Void

    private var entries: [NotchQuotaEntry] { appModel.notchEntries }

    private func displayName(_ providerId: String) -> String {
        appModel.orderedProviders.first { $0.id == providerId }?.displayName ?? providerId
    }

    private func window(_ entry: NotchQuotaEntry) -> QuotaWindow? {
        appModel.snapshotsByProvider[entry.providerId]?.quotas.first { $0.label == entry.windowLabel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if entries.isEmpty {
                Text(L("Sem dados de cota"))
                    .font(.system(size: 11))
                    .foregroundStyle(NotchPalette.inkDim)
            } else {
                ForEach(entries) { entry in
                    if let window = window(entry) {
                        NotchQuotaRow(
                            name: displayName(entry.providerId),
                            providerId: entry.providerId,
                            window: window,
                            entry: entry
                        )
                    }
                }
            }
        }
        .frame(width: 330, alignment: .leading)
        // O painel inteiro é o alvo do clique — mirar numa linha específica de 20pt
        // debaixo do notch seria um exercício de pontaria, não uma interação.
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private var header: some View {
        HStack(spacing: 7) {
            BrandMark(size: 13)
                .foregroundStyle(NotchPalette.ink)
            Text("OkTally")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NotchPalette.ink)
            Spacer(minLength: 6)
            Text(L("Clique para abrir"))
                .font(.system(size: 9, weight: .medium))
                .tracking(Theme.labelTracking)
                .foregroundStyle(NotchPalette.inkDim)
        }
    }
}

/// Uma cota por linha. A ordem de leitura é fixa — quem, qual janela, quanto resta,
/// quando volta — para o olho descer uma coluna só de porcentagens.
private struct NotchQuotaRow: View {
    let name: String
    let providerId: String
    let window: QuotaWindow
    let entry: NotchQuotaEntry

    private var remaining: Double? { entry.remaining }

    /// Número neutro quando há folga, cor quando aperta — mesma regra do
    /// `QuotaPresentation.valueColor`, mas com o off-white do painel no lugar do
    /// `.primary` (que sobre preto sólido dependeria do tema do sistema).
    private var valueColor: Color {
        guard let remaining else { return NotchPalette.ink }
        return remaining > 0.30 ? NotchPalette.ink : QuotaPresentation.color(remaining: remaining)
    }

    var body: some View {
        HStack(spacing: 8) {
            IconChip(glyph: ProviderPalette.glyph(forId: providerId),
                     color: ProviderPalette.color(for: providerId),
                     size: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchPalette.ink)
                    .lineLimit(1)
                Text(WindowLabelCatalog.displayLabel(window.label))
                    .font(.system(size: 9))
                    .foregroundStyle(NotchPalette.inkDim)
                    .lineLimit(1)
            }
            .frame(width: 104, alignment: .leading)

            if let remaining {
                QuotaCapsuleBar(remaining: remaining,
                                color: QuotaPresentation.color(remaining: remaining),
                                height: 5,
                                track: AnyShapeStyle(NotchPalette.track))
            } else {
                Spacer(minLength: 0)
            }

            Text(QuotaPresentation.remainingValueText(window.shape))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .frame(width: 52, alignment: .trailing)

            Text(QuotaPresentation.resetCompactText(window.shape) ?? "—")
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(NotchPalette.inkDim)
                .lineLimit(1)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

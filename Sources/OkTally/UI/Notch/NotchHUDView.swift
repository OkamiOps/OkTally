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

    var body: some View {
        NotchWing(segment: appModel.notchWings.leading, showsBrandFallback: true)
            .notchBottomRule(appModel.notchBottomBar, growingToward: .leading)
    }
}

struct NotchCompactTrailing: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        NotchWing(segment: appModel.notchWings.trailing, showsBrandFallback: false)
            .notchBottomRule(appModel.notchBottomBar, growingToward: .trailing)
    }
}

// MARK: - Barra inferior

/// A barra fina da borda inferior do notch fechado — um traço de 2,5pt com o quanto RESTA
/// da cota escolhida (`notchBottomSlot`; em automático, a mais apertada).
///
/// ## Por que ela é desenhada em duas metades
///
/// A região central do painel fechado é o recorte físico: ali não existe pixel nenhum,
/// e nada desenhado no meio apareceria. Os únicos lugares com tela são as duas asas. A
/// barra é, portanto, uma linha só que o recorte INTERROMPE — e as duas metades precisam
/// ler como uma coisa, não como dois medidores diferentes.
///
/// O que faz isso funcionar é a âncora: as duas metades crescem A PARTIR do recorte para
/// fora, com o mesmo valor. Cheia, o traço acompanha toda a borda inferior das duas asas;
/// esvaziando, ele recua simetricamente na direção do recorte. Simetria é o que o olho
/// usa para decidir que são um elemento só.
///
/// Cheia = FOLGA, igual a `QuotaCapsuleBar` e a todo o resto do app. Espelhar a âncora
/// não inverte essa leitura — só troca de que lado o preenchimento começa.
///
/// Cor pela escala de perigo (`QuotaPresentation.color(remaining:)`) e não pela
/// identidade do provedor: num traço de 2,5pt a cor não consegue fazer as duas coisas, e
/// quem é o provedor já está dito pelo chip logo acima, com muito mais clareza do que uma
/// linha de dois pixels conseguiria. O que só a barra pode dizer é "está apertando".
///
/// No estado EXPANDIDO ela não existe: o `DynamicNotchKit` só desenha as asas em
/// `.compact`, e o painel aberto já traz uma `QuotaCapsuleBar` própria por linha — repetir
/// o mesmo número num traço no rodapé seria ruído.
struct NotchBottomRule: View {
    let bar: NotchBottomBar?
    /// Para que lado esta metade cresce (o lado OPOSTO ao recorte).
    let growingToward: HorizontalEdge

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
        if let bar {
            GeometryReader { geo in
                ZStack(alignment: growingToward == .leading ? .trailing : .leading) {
                    Capsule().fill(NotchPalette.track)
                    Capsule()
                        .fill(QuotaPresentation.color(remaining: bar.remaining))
                        .frame(width: max(Self.thickness,
                                          geo.size.width * Theme.clampFraction(bar.remaining)))
                        .animation(.easeInOut(duration: 0.3), value: bar.remaining)
                }
            }
            .frame(height: Self.thickness)
        }
    }
}

private extension View {
    /// Pendura a metade da barra na borda inferior da asa, sem alterar a altura dela: a
    /// asa continua medindo o que o chip mede, e o traço mora no respiro que o pacote já
    /// reserva embaixo. Um `overlay` (e não um `VStack`) justamente para o texto do chip
    /// não subir 2,5pt quando a barra aparece.
    func notchBottomRule(_ bar: NotchBottomBar?, growingToward edge: HorizontalEdge) -> some View {
        overlay(alignment: .bottom) {
            NotchBottomRule(bar: bar, growingToward: edge)
                // Alinhada pelo fundo do chip e EMPURRADA para dentro do respiro do
                // pacote — sem o deslocamento a barra sublinharia o chip, no meio do
                // painel, em vez de correr pela borda de baixo dele.
                .offset(y: NotchBottomRule.reservedBottomInset - NotchBottomRule.bottomGap)
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

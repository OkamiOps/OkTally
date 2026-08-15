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
    ///
    /// `nil` = "ocupe o que houver". É o caso da ilha flutuante: lá o painel não chega
    /// partido em dois, a barra é irmã das asas dentro da mesma pílula, e a largura é a
    /// que o layout já resolveu — medir de novo seria inventar um número que já existe.
    let totalWidth: CGFloat?

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
            if let totalWidth {
                if totalWidth > 0 {
                    track(bar: bar, width: totalWidth)
                        .frame(width: totalWidth, height: Self.thickness)
                }
            } else {
                // A altura é fixa porque é a ESPESSURA DO TRAÇO, não uma altura de
                // conteúdo — a mesma constante do caso medido. É ela que dá ao
                // `GeometryReader` (que sozinho não tem tamanho ideal) algo para preencher.
                GeometryReader { proxy in
                    track(bar: bar, width: proxy.size.width)
                }
                .frame(height: Self.thickness)
            }
        }
    }

    private func track(bar: NotchBottomBar, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // O trilho precisa ser VISÍVEL: sem ele não há proporção, e sem proporção
            // não dá para ver o quanto falta — só o quanto sobrou em pixels soltos.
            Capsule().fill(NotchPalette.ruleTrack)
            Capsule()
                .fill(QuotaPresentation.color(remaining: bar.remaining))
                .frame(width: max(Self.thickness, width * Theme.clampFraction(bar.remaining)))
                .animation(.easeInOut(duration: 0.3), value: bar.remaining)
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

// MARK: - Ilha flutuante

/// O painel quando NENHUMA tela tem recorte — tampa fechada, monitor externo, iMac.
///
/// ## Por que existe
///
/// A versão anterior tratava "sem notch" como "sem painel". Só que o dono trabalha em
/// clamshell com dois monitores externos: a tela embutida some da lista do sistema e o
/// painel se escondia justamente na hora em que ele mais precisava ver as cotas. Sem
/// recorte não há o que abraçar — então a pílula se desenha inteira.
///
/// ## O que muda em relação ao modo notch, e o que NÃO muda
///
/// O conteúdo é o mesmo: as duas asas com chip + valor, a barra contínua no rodapé, e a
/// mesma lista densa quando expande. O que muda é só a moldura — sem vão central (não há
/// recorte para contornar) e uma borda de branco a 8%, que é o que impede a pílula de
/// virar um buraco sem forma contra um wallpaper escuro. No modo notch essa borda seria um
/// erro: lá o painel PRECISA se confundir com o preto do hardware.
///
/// ## Por que os cantos de cima são RETOS
///
/// A primeira versão saiu com a pílula toda arredondada, pendurada logo abaixo da barra de
/// menu — e o dono viu o que ela era: uma janelinha flutuando no meio da tela, por cima da
/// barra de ferramentas do navegador. A pílula agora encosta na borda de cima da tela e
/// ocupa o miolo vazio da própria barra de menu, e é o canto reto em cima com o canto
/// redondo embaixo que faz o olho ler "a tela tem um recorte aqui" em vez de "um app
/// colocou uma janela aqui". Arredondar em cima uma coisa que está colada na borda só
/// mostraria um vinco de wallpaper nos dois cantos, denunciando a janela.
struct NotchIslandView: View {
    @ObservedObject var appModel: AppModel
    let isExpanded: Bool
    /// Clique: abre o popover. Mesmo gesto e mesmo destino do modo notch.
    let onOpen: () -> Void
    /// Entrou/saiu com o cursor. A POLÍTICA (expandir na hora, fechar com atraso) mora no
    /// painel, junto com a do modo notch — a view só relata o que o mouse fez.
    let onHover: (Bool) -> Void
    /// O dono está arrastando a pílula pelo topo. A view não sabe para ONDE: quem move a
    /// janela é o painel, que lê a posição do cursor em coordenadas de TELA. Se a conta
    /// saísse da translação do gesto, ela se morderia — a janela anda, o gesto passa a
    /// medir a partir de uma view que andou junto, e a pílula travaria no lugar.
    var onDragChanged: () -> Void = {}
    var onDragEnded: () -> Void = {}
    /// Duplo clique: de volta ao centro.
    var onRecenter: () -> Void = {}

    /// Em cima, zero: a pílula encosta na borda da tela e canto redondo ali só mostraria
    /// wallpaper. Embaixo, o mesmo 22pt de "asa" do modo notch fechado — expandido sobe
    /// para 24, porque uma lista de cinco linhas com as pontas de uma cápsula viraria um
    /// comprimido, não um painel.
    private var bottomRadius: CGFloat { isExpanded ? 24 : 22 }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        content
            .background(shape.fill(.black))
            .overlay(
                // Um fio, não uma moldura: contra um wallpaper escuro é ele que devolve o
                // contorno da pílula; contra um claro ele desaparece e o preto se vira
                // sozinho.
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
            .contentShape(shape)
            // Declarado ANTES do clique simples de propósito: com os dois registrados, o
            // SwiftUI segura o clique simples até o intervalo do duplo passar, e o popover
            // não abre no primeiro clique de um duplo clique de recentrar.
            .onTapGesture(count: 2, perform: onRecenter)
            .onTapGesture(perform: onOpen)
            // O limiar é o que separa clique de arrasto: sem ele, o tremor da mão entre
            // apertar e soltar viraria um micro-arrasto e mataria o clique que abre o
            // popover.
            .gesture(
                DragGesture(minimumDistance: NotchIslandGeometry.dragThreshold)
                    .onChanged { _ in onDragChanged() }
                    .onEnded { _ in onDragEnded() }
            )
            .onHover(perform: onHover)
    }

    @ViewBuilder
    private var content: some View {
        if isExpanded {
            NotchExpandedView(appModel: appModel, onOpen: onOpen)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
        } else {
            collapsed
        }
    }

    /// Fechado: asa, marca, asa — e a barra contínua embaixo.
    ///
    /// As asas se aproximam porque não há recorte entre elas, e a marca ocupa o miolo que
    /// sobra. Ela não é enfeite: fechada, a pílula é a única coisa do app visível na tela,
    /// e sem a marca dois números soltos num comprimido preto não dizem de quem são.
    private var collapsed: some View {
        HStack(spacing: 10) {
            NotchWing(segment: appModel.notchWings.leading, showsBrandFallback: false)
            // Menor e mais apagada que as asas de propósito. No primeiro corte ela saiu
            // do mesmo tamanho dos chips e em cinza médio, e o olho lia TRÊS chips — um
            // deles sem número. Ela não é dado: é assinatura, e o lugar dela é atrás.
            BrandMark(size: 11)
                .foregroundStyle(NotchPalette.ink.opacity(0.38))
            NotchWing(segment: appModel.notchWings.trailing, showsBrandFallback: false)
        }
        // O respiro onde a barra mora. É gutter da barra, não altura de conteúdo: a
        // barra é um traço de espessura fixa, e sem reservar o lugar dela o `overlay`
        // passaria por cima dos números.
        .padding(.bottom, 7)
        // `overlay` e não uma linha do `VStack`, de propósito: a barra sem largura
        // medida é gulosa (é um `GeometryReader`), e como filha do empilhamento ela
        // esticaria a pílula até a borda da tela. Num overlay ela recebe exatamente o
        // tamanho de quem a hospeda — a largura das asas — e não opina sobre ele.
        .overlay(alignment: .bottom) {
            NotchBottomRule(bar: appModel.notchBottomBar, totalWidth: nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .padding(.bottom, 5)
    }
}

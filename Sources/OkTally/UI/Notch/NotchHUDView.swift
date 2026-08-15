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
    /// Trilho dos tracinhos fechados. Mais forte que o das barras expandidas de
    /// propósito: com 3,5pt de largura contra preto puro, um trilho a 14% some, e aí um
    /// tracinho de 26% deixa de se ler como "um quarto do slot" e vira um ponto solto.
    static let tickTrack = Color.white.opacity(0.24)
}

// MARK: - Fechado

/// O que abraça o notch quando o painel está discreto: a marca de um lado, um tracinho
/// por cota do outro.
///
/// Tracinho, e não número: fechado o painel divide a altura da barra de menu com o
/// relógio e os ícones do sistema, e texto nesse tamanho seria a mesma sopa ilegível que
/// acabou de sair da barra. O tracinho diz "quanto sobra" pela ALTURA preenchida, que se
/// lê de relance e a dois metros.
struct NotchCompactLeading: View {
    var body: some View {
        BrandMark(size: 13)
            .foregroundStyle(NotchPalette.ink)
    }
}

struct NotchCompactTrailing: View {
    /// Observa o modelo em vez de receber a lista pronta: `DynamicNotch` guarda o
    /// conteúdo UMA vez, na criação do painel, então uma lista passada por valor
    /// congelaria nos números do momento em que o app subiu.
    @ObservedObject var appModel: AppModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(appModel.notchEntries) { entry in
                NotchTick(entry: entry)
            }
        }
    }
}

/// Um tracinho vertical: trilho fraco + preenchimento do que resta, de baixo para cima.
private struct NotchTick: View {
    let entry: NotchQuotaEntry

    /// Cor de IDENTIDADE do provedor, não da escala de perigo — é ela que diz de quem é o
    /// tracinho quando cinco deles estão lado a lado. A exceção é o vermelho da escala:
    /// abaixo de 10% a pergunta deixa de ser "de quem é" e passa a ser "o que está
    /// acabando", e aí o magenta da marca ganha do roxo/lima/âmbar do provedor.
    private var color: Color {
        entry.danger == .critical ? Theme.Brand.neonMagenta : ProviderPalette.color(for: entry.providerId)
    }

    /// Saldos não têm porcentagem: o tracinho fica cheio e apenas identifica o provedor.
    /// Um piso de 12% garante que 0% ainda desenhe um ponto — um tracinho vazio seria
    /// indistinguível de "esse provedor sumiu".
    private var fill: Double {
        guard let remaining = entry.remaining else { return 1 }
        return max(0.12, Theme.clampFraction(remaining))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(NotchPalette.tickTrack)
                Capsule()
                    .fill(color)
                    .frame(height: max(geo.size.width, geo.size.height * fill))
            }
        }
        .frame(width: 4, height: 12)
        .animation(.easeInOut(duration: 0.3), value: fill)
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

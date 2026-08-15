// Sources/OkTally/UI/QuotaLedger.swift
import SwiftUI

/// A tabela densa de cotas — a resposta estrutural ao problema que a grade de cards da
/// Visão geral nunca resolveu: **rodapés irregulares**.
///
/// A causa nunca foi o alinhamento, foi a unidade. Enquanto a unidade da tela era o
/// *provedor*, cada célula tinha um volume de conteúdo diferente (OpenRouter só tem
/// saldo, Copilot tem duas janelas, Claude tem duas mais sparkline) e um `LazyVGrid`
/// dava a linha inteira a altura do card mais alto, deixando um buraco de até 200pt ao
/// lado do card curto. Esticar todos até o mais alto já foi tentado e reprovado: enche
/// de vazio justamente quem tem pouco a dizer.
///
/// Aqui a unidade passa a ser a **janela de cota**. Toda janela tem exatamente o mesmo
/// conteúdo — quem, qual, quanto falta, quando volta — então toda linha tem a mesma
/// altura por construção, sem nenhuma altura fixa e sem esticar nada. O buraco deixa de
/// existir porque a geometria que o produzia deixou de existir.
enum QuotaPressure: Int, CaseIterable {
    case tight, watch, comfortable, balance

    /// Agrupamento por PRESSÃO, não por tipo de janela. Classificar por tipo exigiria
    /// interpretar o rótulo cru do provedor ("percent", "premium", "chat", "5h"), que é
    /// texto arbitrário de dez APIs diferentes; a pressão sai do próprio dado e ainda
    /// responde a pergunta que traz o dono à tela ("o que está apertado?").
    static func of(_ shape: QuotaShape) -> QuotaPressure {
        guard let remaining = QuotaPresentation.remainingFraction(shape) else { return .balance }
        if remaining <= 0.30 { return .tight }
        if remaining <= 0.60 { return .watch }
        return .comfortable
    }

    var title: String {
        switch self {
        case .tight: return L("Sob pressão")
        case .watch: return L("Em observação")
        case .comfortable: return L("Com folga")
        case .balance: return L("Saldos")
        }
    }
}

/// Uma janela de cota de um provedor, achatada para virar linha de tabela.
struct QuotaLedgerEntry: Identifiable {
    let providerId: String
    let providerName: String
    let window: QuotaWindow

    var id: String { providerId + "/" + window.label }
    var remaining: Double? { QuotaPresentation.remainingFraction(window.shape) }
    var pressure: QuotaPressure { QuotaPressure.of(window.shape) }
}

/// Card único com todas as janelas, agrupadas por pressão e ordenadas da mais apertada
/// para a mais folgada. Substitui a grade de oito a dez cards por UM objeto — que é o
/// "agrupamento claro" das referências, e o que permite a densidade alta sem a tela
/// virar um mosaico de retângulos.
struct QuotaLedgerCard: View {
    let title: String
    let entries: [QuotaLedgerEntry]
    /// `nil` quando a linha não navega para lugar nenhum (painel de um provedor só).
    var onSelect: ((String) -> Void)?

    private var groups: [(pressure: QuotaPressure, rows: [QuotaLedgerEntry])] {
        QuotaPressure.allCases.compactMap { pressure in
            let rows = entries
                .filter { $0.pressure == pressure }
                .sorted { ($0.remaining ?? 2) < ($1.remaining ?? 2) }
            return rows.isEmpty ? nil : (pressure, rows)
        }
    }

    var body: some View {
        DashboardCard(padding: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.bottom, Theme.Space.sm)
                ForEach(groups, id: \.pressure) { group in
                    // Só rotula o grupo quando há mais de um: com uma faixa só, o título
                    // repetiria o que a tabela inteira já é.
                    if groups.count > 1 {
                        GroupBanner(pressure: group.pressure, count: group.rows.count)
                    }
                    ForEach(group.rows) { entry in
                        QuotaLedgerRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect?(entry.providerId) }
                    }
                }
            }
        }
    }
}

/// Faixa de grupo: ponto na cor da pressão, rótulo minúsculo em caixa alta e a contagem.
/// É o único lugar onde a cor semântica aparece em área (e não só num número), porque
/// aqui ela é o critério do agrupamento.
private struct GroupBanner: View {
    let pressure: QuotaPressure
    let count: Int

    private var tint: Color {
        switch pressure {
        case .tight: return Theme.Brand.neonMagenta
        case .watch: return Theme.Brand.heatOrange
        case .comfortable: return Theme.accent
        case .balance: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Circle().fill(tint).frame(width: 6, height: 6)
            SectionHeader(pressure.title)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(Theme.border())
                .frame(height: 1)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.xs)
    }
}

/// A linha da tabela. Ordem de leitura fixa da esquerda para a direita — identidade,
/// quem, qual janela, quanto falta (barra), quando volta, o número — para o olho descer
/// uma coluna só de percentuais.
///
/// A barra vive NO MEIO da linha, não abaixo dela. Numa janela de 700pt+ a barra
/// embaixo deixava um vão morto de uns 250pt no centro de cada linha; ocupando esse vão
/// ela vira a coluna que dá escala à tabela inteira e a linha passa a ter uma altura só.
struct QuotaLedgerRow: View {
    let entry: QuotaLedgerEntry
    /// Mesma linha desenhada DENTRO do bloco-herói: off-white no lugar da hierarquia
    /// semântica do sistema (que sobre gradiente saturado some), sem o chip de
    /// identidade (o bloco inteiro já é da cor do provedor) e sem o nome (é o dele).
    var onHero: Bool = false

    private var identity: Color { ProviderPalette.color(for: entry.providerId) }
    /// Off-white REBAIXADO dentro do herói: a 100% a barra secundária ficava idêntica à
    /// barra principal logo acima e as duas se liam como uma repetição.
    private var barColor: Color { onHero ? Theme.onHero.opacity(0.55) : identity }

    var body: some View {
        // Orçamento de largura pensado para o MENOR tamanho possível da janela (700pt
        // com a sidebar no mínimo ⇒ detalhe ~500 ⇒ ~410 dentro dos paddings): a soma dos
        // pisos das seis colunas cabe ali. Com pisos maiores a `HStack` não conseguia
        // encolher e a tabela vazava por fora do card, cortada nas duas pontas.
        HStack(spacing: 6) {
            if !onHero {
                IconChip(glyph: ProviderPalette.glyph(forId: entry.providerId), color: identity, size: 18)
                Text(entry.providerName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
            }
            Text(WindowLabelCatalog.displayLabel(entry.window.label))
                .font(.system(size: 11))
                .foregroundStyle(onHero ? AnyShapeStyle(Theme.onHero.opacity(0.85)) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .lineLimit(1)
                // Piso de largura: na janela no tamanho mínimo (700pt, detalhe ~500) as
                // duas células flexíveis dividiam a sobra meio a meio e o rótulo caía
                // para "5h ses…" enquanto a barra ficava com espaço de sobra. Com o piso,
                // quem encolhe primeiro é a barra, que continua legível como stub.
                .frame(minWidth: 96, maxWidth: .infinity, alignment: .leading)
            // Cota sem percentual (saldo puro) não tem barra: um trilho vazio mentiria
            // dizendo "zero restante". A célula continua ocupando a coluna para as
            // linhas não se desalinharem.
            Group {
                if let remaining = entry.remaining {
                    QuotaCapsuleBar(remaining: remaining, color: barColor, height: 6,
                                    track: onHero ? AnyShapeStyle(Color.black.opacity(0.22)) : nil)
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 40, maxWidth: .infinity)
            // String vazia, não um travessão: um "—" na coluna de contagem regressiva
            // é lido como valor ("menos"?) e some junto com a coluna quando ela não tem
            // nada a dizer — que é o caso de todo saldo puro.
            Text(QuotaPresentation.resetCompactText(entry.window.shape) ?? "")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(onHero ? AnyShapeStyle(Theme.onHero.opacity(0.7)) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .lineLimit(1)
                .frame(width: 50, alignment: .trailing)
            Text(QuotaPresentation.remainingValueText(entry.window.shape))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(onHero ? Theme.onHero : QuotaPresentation.valueColor(remaining: entry.remaining))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 7)
        .help(entry.window.shape.isEstimated
              ? L("Estimativa local, não confirmada pelo provedor") : "")
    }
}

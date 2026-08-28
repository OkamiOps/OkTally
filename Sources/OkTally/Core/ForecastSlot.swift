import Foundation

/// A janela que serve de alvo para a previsão de uso.
///
/// A preferência só guarda a intenção do dono. Decidir se a janela ainda existe e
/// calcular a previsão pertencem ao engine, para que uma escolha órfã nunca torne a
/// preferência inválida nem acople persistência à coleta de uso.
enum ForecastSlot: Equatable, Hashable {
    /// Deixa o engine escolher a janela mais relevante.
    case automatic
    case window(providerId: String, windowLabel: String)

    /// Forma persistida. A ausência de valor e uma escolha automática explícita são o
    /// mesmo estado, portanto `.automatic` é representado pela string vazia.
    var stored: String {
        switch self {
        case .automatic:
            return ""
        case .window(let providerId, let windowLabel):
            return "\(providerId)\u{1}\(windowLabel)"
        }
    }

    /// Não falha: preferências ausentes, corrompidas ou de um formato desconhecido
    /// voltam ao modo automático. O primeiro separador delimita o provider; os demais
    /// fazem parte do rótulo da janela.
    init(stored: String?) {
        guard let stored, !stored.isEmpty,
              case let parts = stored.split(separator: "\u{1}", maxSplits: 1),
              parts.count == 2
        else {
            self = .automatic
            return
        }

        self = .window(providerId: String(parts[0]), windowLabel: String(parts[1]))
    }
}

// Sources/OkTally/Core/QuotaSlot.swift
import Foundation

/// O que ocupa UM lugar de exibição — uma asa do notch ou o número da barra de menu.
///
/// O app já sabia identificar uma janela de cota por `providerId` + `windowLabel` (é a
/// identidade que o `MenuBarPin` usa). O que faltava era o dono poder dizer *qual* delas
/// vai em *qual* lugar: até aqui o notch fechado mostrava um tracinho por cota e a barra
/// mostrava sempre a mais crítica, sem escolha nenhuma.
///
/// `.automatic` continua sendo o padrão e o modo mais útil na maior parte do tempo — é o
/// único que reage sozinho quando a cota que aperta muda ao longo do dia. A escolha
/// explícita existe para quem sabe qual número quer ver o dia inteiro.
enum QuotaSlot: Equatable, Hashable {
    /// A pior janela disponível no momento (e, no caso da asa direita, a pior das que
    /// sobraram depois da esquerda).
    case automatic
    case window(providerId: String, windowLabel: String)

    /// Forma persistida. String vazia é `.automatic` — assim uma preferência nunca
    /// gravada e uma explicitamente automática são a mesma coisa, e não há um terceiro
    /// estado "indefinido" para o resto do app tratar.
    ///
    /// O separador é o mesmo `\u{1}` do `MenuBarPin.stored`, de propósito: é o caractere
    /// que não aparece nem em id de provedor nem em rótulo de janela.
    var stored: String {
        switch self {
        case .automatic: return ""
        case .window(let providerId, let windowLabel): return "\(providerId)\u{1}\(windowLabel)"
        }
    }

    /// Não falha: qualquer coisa que não seja um par válido vira `.automatic`. Uma
    /// preferência corrompida (ou de um formato futuro) tem que degradar para o padrão,
    /// nunca derrubar a barra de menu.
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

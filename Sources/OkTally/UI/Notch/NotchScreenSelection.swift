// Sources/OkTally/UI/Notch/NotchScreenSelection.swift
import Foundation

/// O que o painel do notch precisa saber sobre uma tela — e nada além disso.
///
/// Existe para tirar a decisão "em qual tela o painel vive" de dentro do `NSScreen`, que
/// não dá para instanciar num teste. O `id` é a posição da tela na lista original, que é
/// como o chamador reencontra o `NSScreen` correspondente.
struct NotchScreenDescriptor: Equatable {
    let id: Int
    /// Recorte físico: `safeAreaInsets.top > 0` **e** as duas áreas auxiliares presentes
    /// (é delas que sai a largura do notch).
    let hasNotch: Bool
    /// A tela PRIMÁRIA (`NSScreen.screens[0]`), onde a barra de menu mora. Deixou de ser
    /// um campo decorativo: é ela que hospeda a ilha flutuante quando não há recorte em
    /// tela nenhuma. Para escolher a tela COM notch ele continua sendo deliberadamente
    /// ignorado — ver `select(from:)`.
    let isPrimary: Bool
}

/// Onde o painel aparece e com que forma.
///
/// São duas FORMAS, não duas telas: o mesmo conteúdo é desenhado abraçando um recorte
/// físico (`.notch`) ou como uma pílula autônoma no topo (`.floating`). Quem decide é a
/// existência do recorte, e a decisão é um valor — não um `if` espalhado pelo controller.
enum NotchScreenPlacement: Equatable {
    /// Esta tela tem recorte físico: o painel se cola nele.
    case notch(NotchScreenDescriptor)
    /// Nenhuma tela tem recorte: ilha flutuante nesta (a primária).
    case floating(NotchScreenDescriptor)

    var screen: NotchScreenDescriptor {
        switch self {
        case let .notch(descriptor), let .floating(descriptor): return descriptor
        }
    }
}

/// Escolhe onde o painel do notch vive.
enum NotchScreenSelection {
    /// A primeira tela COM notch; sem nenhuma, a tela primária em modo ilha; sem telas,
    /// nada.
    ///
    /// ## Por que "primeira com notch" e não "principal"
    ///
    /// Ao plugar um monitor externo ele vira, com frequência, a tela principal
    /// (`NSScreen.screens[0]`), e o painel tem de continuar no MacBook mesmo assim. Por
    /// isso `isPrimary` não entra na escolha do caso `.notch`.
    ///
    /// ## Por que existe o caso `.floating`
    ///
    /// A regra antiga parava aqui: sem tela com recorte, painel nenhum. Só que o jeito
    /// que o dono trabalha é exatamente esse — tampa fechada, dois monitores externos — e
    /// a tela embutida **nem aparece** na lista nesse momento. O painel se escondia de
    /// propósito justo quando era mais útil. Sem recorte não há o que abraçar, mas há o
    /// que desenhar: a pílula inteira, na tela primária (a que tem a barra de menu).
    static func select(from screens: [NotchScreenDescriptor]) -> NotchScreenPlacement? {
        if let notched = screens.first(where: { $0.hasNotch }) {
            return .notch(notched)
        }
        // `first(isPrimary)` com a primeira da lista como rede: no meio de uma
        // reconfiguração o AppKit chega a devolver listas sem nenhuma tela marcada como
        // primária, e desistir ali deixaria o dono sem painel bem na hora do
        // plugar/desplugar.
        guard let host = screens.first(where: { $0.isPrimary }) ?? screens.first else { return nil }
        return .floating(host)
    }
}

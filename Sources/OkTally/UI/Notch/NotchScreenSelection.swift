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
    /// Guardado de propósito mesmo sem ser usado na escolha: é justamente o critério que
    /// NÃO pode influenciar. Ver `select(from:)`.
    let isPrimary: Bool
}

/// Escolhe a tela do painel do notch.
enum NotchScreenSelection {
    /// A primeira tela COM notch, sempre — e nenhuma quando não houver.
    ///
    /// "Principal" é deliberadamente ignorado: ao plugar um monitor externo ele vira, com
    /// frequência, a tela principal (`NSScreen.screens[0]`), e o painel tem de continuar
    /// no MacBook mesmo assim. Em compensação, tampa fechada (clamshell) faz a embutida
    /// sumir da lista e aí a resposta correta é `nil` — sem painel, sem estrago.
    static func select(from screens: [NotchScreenDescriptor]) -> NotchScreenDescriptor? {
        screens.first { $0.hasNotch }
    }
}

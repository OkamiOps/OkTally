// Sources/OkTally/Core/Localization.swift
import Foundation

/// Localização com o português como língua-base: as CHAVES são as próprias strings em
/// PT (o texto original do app), e `en.lproj/Localizable.strings` fornece a tradução.
/// Chave ausente cai no PT — nunca aparece uma chave crua na tela.
///
/// `Bundle.module` é obrigatório: strings de recurso de um pacote SPM não vivem no
/// `Bundle.main`, então `Text("literal")` do SwiftUI (que só olha o main) não enxergaria
/// as traduções — todo texto visível passa por `L`/`LF`.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

/// Variante com interpolação: `LF("Reseta em %@", tempo)`.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

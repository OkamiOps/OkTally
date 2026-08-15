// Sources/OkTally/UI/DesignSystem/StaticRender.swift
import SwiftUI

/// Sinaliza que a árvore está sendo desenhada por `ImageRenderer` (os PNGs de
/// `docs/assets`), e não numa janela viva. Controles do AppKit não têm representação
/// nesse caminho — `Picker(.segmented)`, por exemplo, sai como um retângulo amarelo com
/// o símbolo de proibido. Quem depende de um controle desses desenha um substituto
/// estático quando a flag está ligada.
///
/// Só o harness de render liga isto. O app nunca liga, então o usuário continua com o
/// controle nativo: semântica de seleção para o VoiceOver, navegação por setas dentro do
/// grupo e o estilo do sistema.
private struct StaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isStaticRender: Bool {
        get { self[StaticRenderKey.self] }
        set { self[StaticRenderKey.self] = newValue }
    }
}

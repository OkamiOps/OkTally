// Sources/OkTally/Core/PinReorder.swift
import Foundation

/// Reordenação dos pinos da barra de menu por arrastar-e-soltar.
///
/// Vive fora da `View` para poder ser testada: a primeira versão calculava o índice do
/// alvo DEPOIS de remover o item arrastado, o que encolhe todos os índices acima da
/// origem — arrastar para baixo parava um slot antes do alvo e a última posição da barra
/// ficava inalcançável. Aqui os dois índices saem da lista original.
enum PinReorder {
    /// Nova ordem, ou `nil` quando o arrasto não muda nada (soltou sobre si mesmo, ou um
    /// dos identificadores não está na lista).
    static func reordered(_ order: [String], dragging: String, onto target: String) -> [String]? {
        guard dragging != target,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: target)
        else { return nil }
        var result = order
        let moved = result.remove(at: from)
        result.insert(moved, at: to)
        return result
    }
}

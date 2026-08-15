// Sources/OkTally/Core/FieldCommit.swift
import Foundation

/// Regras do auto-save das Preferências. Os campos passaram a gravar sozinhos (no Enter
/// e ao perder o foco), então precisam de guardas que o botão "Salvar" antes dava de
/// graça: campo vazio nunca apaga credencial, e valor inalterado não gera escrita.
enum FieldCommit {
    /// Valor a persistir, ou `nil` quando a edição deve ser ignorada.
    static func sanitized(_ raw: String, previous: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != previous.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return trimmed
    }

    /// Saldo em USD, aceitando vírgula decimal. `nil` para valores não positivos ou lixo.
    ///
    /// Notação científica ("1e3", "2E-1") é recusada de propósito: `Double(_:)` aceita
    /// esse formato e converteria silenciosamente para um limiar de alerta inesperado —
    /// exatamente o "valor aceito errado gera alerta errado" que este campo evita.
    static func lowBalance(_ raw: String) -> Double? {
        guard let value = amount(raw), value > 0 else { return nil }
        return value
    }

    /// Quantidade não negativa, aceitando vírgula decimal — os campos de crédito do MiMo,
    /// onde "usados = 0" é um valor legítimo e não pode ser recusado como o saldo baixo é.
    /// Mesma recusa de notação científica.
    static func amount(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard normalized.lowercased().contains("e") == false else { return nil }
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }
}

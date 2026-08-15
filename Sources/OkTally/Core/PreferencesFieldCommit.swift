// Sources/OkTally/Core/PreferencesFieldCommit.swift
import Foundation

/// Resultado de um commit de campo com auto-save.
enum FieldCommitOutcome<Value: Equatable>: Equatable {
    /// Nada a gravar. O campo volta para `restore`, que é sempre o valor realmente salvo:
    /// deixar o texto vazio na tela faria parecer que a credencial foi apagada.
    case ignored(restore: String)
    /// Grava `value` e mostra `display`.
    case commit(value: Value, display: String)
}

/// Composição das regras de auto-save das Preferências — a guarda do `FieldCommit`, o
/// parser certo para cada campo e o texto de restauração, juntos.
///
/// Vive fora da `PreferencesView` de propósito: dentro dela seriam `private func`
/// inalcançáveis pela suíte, e o que precisa de prova não é o `FieldCommit` isolado e sim
/// esta composição ("limpou o campo e saiu → o valor salvo sobrevive").
enum PreferencesFieldCommit {
    /// Chave de API. `saved` é o valor lido do Keychain, nunca o `@State` do campo — se
    /// viesse do `@State`, "inalterado" compararia o texto consigo mesmo e a guarda seria
    /// inútil.
    static func secret(raw: String, saved: String) -> FieldCommitOutcome<String> {
        guard let value = FieldCommit.sanitized(raw, previous: saved) else {
            return .ignored(restore: saved)
        }
        return .commit(value: value, display: value)
    }

    /// Franquia do MiMo: precisa ser positiva, porque franquia zero não mede nada.
    static func allowance(raw: String, saved: Double?) -> FieldCommitOutcome<Double> {
        let stored = saved.map(credits) ?? ""
        guard let candidate = FieldCommit.sanitized(raw, previous: stored),
              let value = FieldCommit.lowBalance(candidate) else {
            return .ignored(restore: stored)
        }
        return .commit(value: value, display: credits(value))
    }

    /// Créditos usados: zero é legítimo (mês recém-começado), então usa `amount`.
    static func used(raw: String, saved: Double) -> FieldCommitOutcome<Double> {
        let stored = credits(saved)
        guard let candidate = FieldCommit.sanitized(raw, previous: stored),
              let value = FieldCommit.amount(candidate) else {
            return .ignored(restore: stored)
        }
        return .commit(value: value, display: credits(value))
    }

    /// Mesma renderização em `load()` e nos commits — se divergissem, "valor inalterado"
    /// nunca bateria e todo blur gravaria de novo.
    ///
    /// `String(value)` sozinho mostrava "500.0" e "0.0" no campo. Créditos inteiros são
    /// o caso comum, então o ".0" é podado; frações continuam intactas ("750.5"). O
    /// ida-e-volta segue válido porque `Double("500") == 500`.
    static func credits(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}

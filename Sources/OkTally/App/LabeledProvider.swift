// Sources/OkTally/App/LabeledProvider.swift
import Foundation

/// Embrulha um provedor e troca só o `displayName` pelo rótulo da conta ("Claude Code ·
/// Trabalho"). Todo o resto é repassado. Como popover, notch, janela principal, análise e
/// alertas (`Scheduler`) já leem `displayName`, o rótulo chega a todos eles de graça.
///
/// O rótulo é uma closure, e não um valor, porque apelido e e-mail mudam em tempo de
/// execução (renomear nas Preferências) sem recriar o provedor.
final class LabeledProvider: UsageProvider {
    let base: UsageProvider
    private let label: () -> String

    init(base: UsageProvider, label: @escaping () -> String) {
        self.base = base
        self.label = label
    }

    var id: String { base.id }
    var displayName: String { label() }
    var authMethod: AuthMethod { base.authMethod }
    var refreshInterval: TimeInterval { base.refreshInterval }

    func isAuthenticated() async -> Bool { await base.isAuthenticated() }
    func fetchSnapshot() async throws -> ProviderSnapshot { try await base.fetchSnapshot() }
}

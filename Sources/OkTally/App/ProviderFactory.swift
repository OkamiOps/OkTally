// Sources/OkTally/App/ProviderFactory.swift
import Foundation

/// Monta os provedores de UMA conta. É o único lugar que sabe qual plugin corresponde a
/// qual `AccountKind` — o registry, o scheduler e o `AppModel` só enxergam ids.
///
/// Uma conta do Cursor rende dois provedores: o Cursor e o GrokBot gêmeo, que usa a
/// mesma sessão (`cursor#abc` → `cursor-grokbot#abc`).
struct ProviderFactory {
    struct Dependencies {
        let oauthManager: OAuthManaging
        let tokenStore: TokenStoring
        let preferences: PreferencesStore
        let mimoSessionStore: MiMoSessionStore

        /// Dependências inofensivas para testes: nada toca o Keychain nem os
        /// `UserDefaults` reais.
        static func testing(tokenStore: TokenStoring, preferences: PreferencesStore) -> Dependencies {
            let suite = "oktally.tests.factory.\(UUID().uuidString)"
            return Dependencies(
                oauthManager: OAuthManager(store: tokenStore),
                tokenStore: tokenStore,
                preferences: preferences,
                mimoSessionStore: MiMoSessionStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
            )
        }
    }

    let dependencies: Dependencies

    func providers(for account: AccountInstance, all: [AccountInstance]) -> [UsageProvider] {
        let deps = dependencies
        let preferences = deps.preferences
        let id = account.id
        let raw: [UsageProvider]
        switch account.kind {
        case .claude:
            raw = [ClaudeUsageProvider(instanceId: id, oauthManager: deps.oauthManager, tokenStore: deps.tokenStore)]
        case .codex:
            raw = [CodexUsageProvider(instanceId: id, oauthManager: deps.oauthManager, tokenStore: deps.tokenStore)]
        case .supergrok:
            raw = [SuperGrokUsageProvider(instanceId: id, oauthManager: deps.oauthManager, tokenStore: deps.tokenStore)]
        case .openrouter:
            raw = [OpenRouterUsageProvider(instanceId: id, apiKeyProvider: { preferences.openRouterAPIKey })]
        case .minimax:
            raw = [MiniMaxUsageProvider(
                instanceId: id,
                apiKeyProvider: { preferences.minimaxAPIKey },
                region: { preferences.minimaxRegionRaw == "china" ? .china : .global }
            )]
        case .opencode:
            raw = [OpenCodeUsageProvider(instanceId: id, apiKeyProvider: { preferences.openCodeAPIKey })]
        case .cursor:
            raw = [
                CursorUsageProvider(instanceId: id),
                GrokBotUsageProvider(instanceId: AccountID.grokBotId(forCursor: id))
            ]
        case .grokbot:
            // O GrokBot nunca é uma conta própria: nasce junto da conta do Cursor.
            raw = []
        case .copilot:
            raw = [CopilotUsageProvider()]
        case .antigravity:
            raw = [AntigravityUsageProvider(instanceId: id)]
        case .mimo:
            raw = [MiMoUsageProvider(
                sessionStore: deps.mimoSessionStore,
                usageFetcher: MiMoWebSession.shared,
                allowanceProvider: { preferences.mimoMonthlyAllowanceCredits },
                usedCreditsProvider: { preferences.mimoUsedCredits }
            )]
        }
        return raw.map { base in
            let baseName = base.displayName
            return LabeledProvider(base: base) {
                // Lido a cada acesso: renomear nas Preferências vale na hora. Se a conta
                // já não está na lista (acabou de ser removida), cai no retrato da criação.
                let current = preferences.accounts
                let latest = current.first { $0.id == id } ?? account
                let siblings = current.contains { $0.id == id } ? current : all
                return AccountLabel.display(for: latest, baseName: baseName, siblings: siblings)
            }
        }
    }
}

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
            raw = [OpenRouterUsageProvider(instanceId: id, apiKeyProvider: { preferences.apiKey(instanceId: id) })]
        case .minimax:
            raw = [MiniMaxUsageProvider(
                instanceId: id,
                apiKeyProvider: { preferences.apiKey(instanceId: id) },
                region: { preferences.minimaxRegionRaw(instanceId: id) == "china" ? .china : .global }
            )]
        case .opencode:
            raw = [OpenCodeUsageProvider(instanceId: id, apiKeyProvider: { preferences.apiKey(instanceId: id) })]
        case .cursor:
            // A legada lê a sessão do IDE; as extras, a sessão própria do Keychain. O
            // GrokBot gêmeo usa exatamente a mesma fonte da conta dele.
            let source: CursorTokenReading = AccountID.isLegacy(id)
                ? CursorTokenReader()
                : KeychainCursorTokenSource(instanceId: id, tokenStore: deps.tokenStore)
            raw = [
                CursorUsageProvider(instanceId: id, tokenReader: source),
                GrokBotUsageProvider(instanceId: AccountID.grokBotId(forCursor: id), tokenReader: source)
            ]
        case .grokbot:
            // O GrokBot nunca é uma conta própria: nasce junto da conta do Cursor.
            raw = []
        case .copilot:
            raw = [CopilotUsageProvider()]
        case .antigravity:
            // A legada lê o IDE; as extras usam o login Google próprio do OkTally.
            raw = [AccountID.isLegacy(id)
                ? AntigravityUsageProvider(instanceId: id)
                : AntigravityUsageProvider(instanceId: id, oauthManager: deps.oauthManager, tokenStore: deps.tokenStore)]
        case .mimo:
            raw = [MiMoUsageProvider(
                sessionStore: deps.mimoSessionStore,
                usageFetcher: MiMoWebSession.shared,
                allowanceProvider: { preferences.mimoMonthlyAllowanceCredits },
                usedCreditsProvider: { preferences.mimoUsedCredits }
            )]
        }
        return raw.map { Self.labeled($0, account: account, all: all, preferences: preferences) }
    }

    /// Embrulha um provedor com o rótulo da conta. O rótulo é lido a cada acesso das
    /// preferências: renomear vale na hora. Se a conta já não está na lista (acabou de
    /// ser removida), cai no retrato da criação.
    static func labeled(_ base: UsageProvider, account: AccountInstance, all: [AccountInstance], preferences: PreferencesStore) -> UsageProvider {
        let baseName = base.displayName
        let id = account.id
        return LabeledProvider(base: base) {
            let current = preferences.accounts
            guard let latest = current.first(where: { $0.id == id }) else {
                return AccountLabel.display(for: account, baseName: baseName, siblings: all)
            }
            return AccountLabel.display(for: latest, baseName: baseName, siblings: current)
        }
    }
}

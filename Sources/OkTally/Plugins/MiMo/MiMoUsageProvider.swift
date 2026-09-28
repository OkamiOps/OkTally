// Sources/OkTally/Plugins/MiMo/MiMoUsageProvider.swift
import Foundation

/// Xiaomi MiMo Token Plan plugin.
///
/// MiMo has no API-key route to quota — the console's "Plan usage" bar comes from
/// `POST /api/v1/usage/token-plan/list`, gated behind the Xiaomi SSO + STS `api-platform`
/// cookie session (see `docs/superpowers/research/plan2-mimo.md`). The only way to read it
/// programmatically is from inside that session, so this plugin fetches through the shared
/// `MiMoWebSession` web view where the user logged in. Falls back to the manual estimate
/// when there's no session.
final class MiMoUsageProvider: UsageProvider {
    let id = "mimo"
    let displayName = "MiMo"
    let authMethod: AuthMethod = .oauthSession
    let refreshInterval: TimeInterval = 600

    /// Quantos ciclos seguidos de 401 aceitamos antes de chamar isso de "entre novamente".
    /// Com `refreshInterval` de 600s são ~30 min tentando em silêncio — tempo de sobra para a
    /// cadeia do SSO se refazer, e curto o bastante para não esconder um logout real.
    static let reauthAfterConsecutiveFailures = 3

    private let sessionStore: MiMoSessionStoring
    private let usageFetcher: MiMoUsageFetching?
    private let allowanceProvider: () -> Double?
    private let usedCreditsProvider: () -> Double
    private let now: () -> Date
    private var consecutiveLiveFailures = 0

    init(
        sessionStore: MiMoSessionStoring,
        usageFetcher: MiMoUsageFetching? = nil,
        allowanceProvider: @escaping () -> Double?,
        usedCreditsProvider: @escaping () -> Double,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionStore = sessionStore
        self.usageFetcher = usageFetcher
        self.allowanceProvider = allowanceProvider
        self.usedCreditsProvider = usedCreditsProvider
        self.now = now
    }

    func isAuthenticated() async -> Bool {
        sessionStore.isLoggedIn || allowanceProvider() != nil
    }

    /// Um 401 aqui NÃO apaga `mimo.loggedIn`.
    ///
    /// Era isso que fazia o MiMo "desconectar toda hora": os cookies de sessão do console são
    /// session-only, então todo lançamento começa com um 401 e depende da recuperação por
    /// reload. Quando essa recuperação falhava uma única vez — rede lenta, cadeia do SSO
    /// ainda rodando — o flag ia a falso, e como a web session só é consultada com o flag
    /// ligado, o caminho nunca mais era tentado: o provider ficava "não configurado" para
    /// sempre, com o `passToken` da Xiaomi vivo em disco o tempo todo. Só um "Sair" explícito
    /// nas Preferências apaga o flag agora; aqui apenas contamos os tropeços e seguimos
    /// tentando no ciclo seguinte.
    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard sessionStore.isLoggedIn, let usageFetcher else { return manualSnapshot() }
        do {
            let snapshot = try await liveSnapshot(usageFetcher: usageFetcher)
            if consecutiveLiveFailures > 0 {
                MiMoLog.session.notice("provider: sessão voltou depois de \(self.consecutiveLiveFailures, privacy: .public) falha(s)")
            }
            consecutiveLiveFailures = 0
            return snapshot
        } catch let error as MiMoConsoleError {
            consecutiveLiveFailures += 1
            MiMoLog.session.error("provider: leitura ao vivo falhou (\(String(describing: error), privacy: .public)), falha nº \(self.consecutiveLiveFailures, privacy: .public)")
            if error == .notLoggedIn, consecutiveLiveFailures >= Self.reauthAfterConsecutiveFailures {
                // Insistiu ciclos seguidos: agora vale pedir login — mas sem apagar o flag,
                // porque a próxima tentativa continua sendo a que tem chance de resolver.
                throw MiMoConsoleError.notLoggedIn
            }
            if let manual = configuredManualSnapshot() { return manual }
            throw MiMoConsoleError.sessionRecovering
        }
    }

    private func liveSnapshot(usageFetcher: MiMoUsageFetching) async throws -> ProviderSnapshot {
        let data = try await usageFetcher.fetchUsageJSON()
        // Classificação tolerante a espaçamento e a corpos que não são JSON — o match literal
        // `"code":401` que existia aqui deixava `{ "code" : 401 }` chegar ao decoder.
        switch MiMoResponseClassifier.classify(data) {
        case .unauthorized: throw MiMoConsoleError.notLoggedIn
        case .unusable: throw MiMoConsoleError.noData
        case .usable: break
        }
        let resp = try JSONDecoder().decode(MiMoUsageResponse.self, from: data)
        // `percent` is a fraction (0.0622 == 6.22%), so ×100 for a 0–100 rolling window.
        var quotas: [QuotaWindow] = []
        if let month = resp.data?.monthUsage?.percent {
            quotas.append(QuotaWindow(label: "mensal", shape: .rollingWindow(
                used: month * 100, limit: 100, windowStart: now(), resetAt: now())))
        }
        if let plan = resp.data?.usage?.percent {
            quotas.append(QuotaWindow(label: "plano", shape: .rollingWindow(
                used: plan * 100, limit: 100, windowStart: now(), resetAt: now())))
        }
        return ProviderSnapshot(providerId: id, fetchedAt: now(), quotas: quotas, usageDetail: nil)
    }

    /// A estimativa manual só é um consolo quando o dono realmente configurou a franquia —
    /// senão ela é um card vazio fingindo que está tudo bem, e aí é melhor deixar o erro subir.
    private func configuredManualSnapshot() -> ProviderSnapshot? {
        allowanceProvider() == nil ? nil : manualSnapshot()
    }

    private func manualSnapshot() -> ProviderSnapshot {
        let shape = QuotaShape.estimated(
            used: usedCreditsProvider(), limit: allowanceProvider(),
            basis: .localTokenCount, resetAt: nil
        )
        return ProviderSnapshot(providerId: id, fetchedAt: now(), quotas: [QuotaWindow(label: "mensal", shape: shape)], usageDetail: nil)
    }
}

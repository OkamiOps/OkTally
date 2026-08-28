import Foundation

protocol KeyValueStore {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func double(forKey key: String) -> Double
    func set(_ value: Double, forKey key: String)
}

extension UserDefaults: KeyValueStore {
    func set(_ value: String?, forKey key: String) {
        set(value as Any?, forKey: key)
    }
}

final class PreferencesStore {
    private let store: KeyValueStore
    private let secretStore: SecretStoring

    private enum Keys {
        // Legacy UserDefaults locations for the 4 API keys below. No longer written to —
        // kept only as migration sources (see `migratedSecret`) so an owner upgrading
        // from an older build doesn't lose a key they already entered.
        static let openRouterAPIKey = "openRouterAPIKey"
        static let mimoAPIKey = "mimoAPIKey"
        static let minimaxAPIKey = "minimaxAPIKey"
        static let openCodeAPIKey = "openCodeAPIKey"

        static let mimoMonthlyAllowanceCredits = "mimoMonthlyAllowanceCredits"
        static let mimoUsedCredits = "mimoUsedCredits"
        static let minimaxRegionRaw = "minimaxRegionRaw"
        static let alertsEnabled = "alertsEnabled"
        static let notchHUDEnabled = "notchHUDEnabled"
        static let menuBarSlot = "menuBarSlot"
        static let notchLeadingSlot = "notchLeadingSlot"
        static let notchTrailingSlot = "notchTrailingSlot"
        static let notchBottomSlot = "notchBottomSlot"
        static let popoverHeroSlot = "popoverHeroSlot"
        static let forecastSlot = "forecastSlot"
        static let usageColorScale = "usageColorScale"
        static let alertPercentThresholds = "alertPercentThresholds"
        static let alertLowBalanceThreshold = "alertLowBalanceThreshold"
        static func refreshInterval(_ providerId: String) -> String { "refreshInterval.\(providerId)" }
        /// Posição horizontal da ilha, POR TELA. A chave carrega o id do display porque
        /// o dono tem dois monitores lado a lado e arrasta a pílula para lugares
        /// diferentes em cada um; uma chave só faria a segunda tela desfazer a primeira.
        static func islandFraction(_ screenId: String) -> String { "islandFraction.\(screenId)" }
    }

    /// Keychain namespace per provider (`com.oktally.app.apikey.<id>` via
    /// `KeychainSecretStore`) — distinct from `UsageProvider.id` only coincidentally
    /// matching it; kept as its own table in case they ever diverge.
    private enum SecretProviderId {
        static let openRouter = "openrouter"
        static let mimo = "mimo"
        static let minimax = "minimax"
        static let openCode = "opencode"
    }

    init(store: KeyValueStore = UserDefaults.standard, secretStore: SecretStoring = KeychainSecretStore()) {
        self.store = store
        self.secretStore = secretStore
    }

    /// API keys are secrets and belong in the Keychain, not `UserDefaults` (see
    /// `SecretStoring`'s doc comment). This reads from the Keychain first; if nothing is
    /// there yet but an older build left a plaintext value in `UserDefaults`, it's moved
    /// into the Keychain and wiped from `UserDefaults` on the spot — a silent one-time
    /// migration, invisible to the caller.
    private func migratedSecret(providerId: String, legacyKey: String) -> String? {
        if let current = secretStore.load(providerId: providerId) { return current }
        guard let legacy = store.string(forKey: legacyKey), !legacy.isEmpty else { return nil }
        // Only scrub the legacy UserDefaults copy once the Keychain write actually
        // succeeds. If `save` throws (Keychain locked, denied ACL, unsigned-build
        // access-group mismatch, etc.), keep `legacy` in UserDefaults so the value
        // isn't lost — the caller still gets it back this call, and migration will be
        // retried on the next read.
        do {
            try secretStore.save(legacy, providerId: providerId)
            store.set(nil, forKey: legacyKey)
        } catch {
            return legacy
        }
        return legacy
    }

    private func setSecret(_ value: String?, providerId: String, legacyKey: String) throws {
        if let value, !value.isEmpty {
            // Write to the Keychain first; only scrub the legacy plaintext location once
            // the write has actually succeeded, so a failed save never destroys the only
            // remaining copy of the key.
            try secretStore.save(value, providerId: providerId)
        } else {
            try secretStore.delete(providerId: providerId)
        }
        store.set(nil, forKey: legacyKey)
    }

    var openRouterAPIKey: String? {
        migratedSecret(providerId: SecretProviderId.openRouter, legacyKey: Keys.openRouterAPIKey)
    }

    /// Throwing setter (rather than a computed-property `set`) so a failed Keychain
    /// write can be surfaced to the caller instead of being silently swallowed — see
    /// `setSecret`.
    func setOpenRouterAPIKey(_ value: String?) throws {
        try setSecret(value, providerId: SecretProviderId.openRouter, legacyKey: Keys.openRouterAPIKey)
    }

    var mimoAPIKey: String? {
        migratedSecret(providerId: SecretProviderId.mimo, legacyKey: Keys.mimoAPIKey)
    }

    func setMimoAPIKey(_ value: String?) throws {
        try setSecret(value, providerId: SecretProviderId.mimo, legacyKey: Keys.mimoAPIKey)
    }

    /// The user-entered monthly Token Plan allowance (in Credits). `nil` means the
    /// owner hasn't configured it yet — MiMo exposes no API-key-authenticated quota
    /// endpoint (confirmed by source; see docs/superpowers/research/plan2-mimo.md),
    /// so this value only ever comes from manual entry in Preferences.
    var mimoMonthlyAllowanceCredits: Double? {
        get { store.string(forKey: Keys.mimoMonthlyAllowanceCredits).flatMap(Double.init) }
        set { store.set(newValue.map { String($0) }, forKey: Keys.mimoMonthlyAllowanceCredits) }
    }

    /// Credits used so far this month, manually updated by the owner. Defaults to 0.
    var mimoUsedCredits: Double {
        get { store.double(forKey: Keys.mimoUsedCredits) }
        set { store.set(newValue, forKey: Keys.mimoUsedCredits) }
    }

    var minimaxAPIKey: String? {
        migratedSecret(providerId: SecretProviderId.minimax, legacyKey: Keys.minimaxAPIKey)
    }

    func setMinimaxAPIKey(_ value: String?) throws {
        try setSecret(value, providerId: SecretProviderId.minimax, legacyKey: Keys.minimaxAPIKey)
    }

    /// Stores `"global"`/`"china"`; defaults to `"global"` when unset. Not a secret, stays
    /// in UserDefaults.
    var minimaxRegionRaw: String? {
        get { store.string(forKey: Keys.minimaxRegionRaw) ?? "global" }
        set { store.set(newValue, forKey: Keys.minimaxRegionRaw) }
    }

    var openCodeAPIKey: String? {
        migratedSecret(providerId: SecretProviderId.openCode, legacyKey: Keys.openCodeAPIKey)
    }

    func setOpenCodeAPIKey(_ value: String?) throws {
        try setSecret(value, providerId: SecretProviderId.openCode, legacyKey: Keys.openCodeAPIKey)
    }

    // MARK: - Notch

    /// Painel do notch ligado. Ligado por padrão (mesma convenção de `alertsEnabled`:
    /// só a string "false" desliga, então nunca ter salvado nada vale como ligado).
    ///
    /// Desligar não é só esconder: o controller destrói a janela flutuante. Quem projeta
    /// a tela, grava vídeo ou simplesmente não quer nada morando no notch fica com a barra
    /// de menu sozinha, que continua completa.
    var notchHUDEnabled: Bool {
        get { store.string(forKey: Keys.notchHUDEnabled) != "false" }
        set { store.set(newValue ? "true" : "false", forKey: Keys.notchHUDEnabled) }
    }

    /// Onde o dono largou a ilha nesta tela, como FRAÇÃO de 0 a 1 da largura — nunca em
    /// pontos.
    ///
    /// A fração é o que sobrevive: trocar a resolução, girar a tela ou plugar outro
    /// monitor com o mesmo id reposiciona a pílula proporcionalmente, enquanto um valor em
    /// pontos jogaria ela para fora da tela. `nil` = nunca arrastada, e quem lê usa o
    /// centro.
    func islandFraction(screenId: String) -> Double? {
        store.string(forKey: Keys.islandFraction(screenId)).flatMap(Double.init)
    }

    func setIslandFraction(_ value: Double?, screenId: String) {
        store.set(value.map { String($0) }, forKey: Keys.islandFraction(screenId))
    }

    // MARK: - Slots de exibição

    /// Qual cota aparece ao lado do símbolo na barra de menu.
    ///
    /// `.automatic` (o padrão) é a regra antiga — a janela mais apertada entre as que o
    /// dono acompanha — e continua sendo a única que reage sozinha quando a cota que
    /// aperta muda ao longo do dia. A escolha explícita existe porque "automático" tira do
    /// dono justamente o número que ele quer olhar o dia inteiro.
    var menuBarSlot: QuotaSlot {
        get { QuotaSlot(stored: store.string(forKey: Keys.menuBarSlot)) }
        set { store.set(newValue.stored.isEmpty ? nil : newValue.stored, forKey: Keys.menuBarSlot) }
    }

    /// A asa ESQUERDA do notch fechado (o lado da marca, antes do recorte).
    var notchLeadingSlot: QuotaSlot {
        get { QuotaSlot(stored: store.string(forKey: Keys.notchLeadingSlot)) }
        set { store.set(newValue.stored.isEmpty ? nil : newValue.stored, forKey: Keys.notchLeadingSlot) }
    }

    /// A asa DIREITA do notch fechado.
    var notchTrailingSlot: QuotaSlot {
        get { QuotaSlot(stored: store.string(forKey: Keys.notchTrailingSlot)) }
        set { store.set(newValue.stored.isEmpty ? nil : newValue.stored, forKey: Keys.notchTrailingSlot) }
    }

    /// A BARRA fina da borda inferior do notch fechado.
    ///
    /// Em automático ela é a cota mais apertada — sem a exclusão que a asa direita faz.
    /// As asas dividem duas informações entre si; a barra é o alarme, e alarme é sempre
    /// sobre a pior cota, ainda que isso a faça coincidir com a asa esquerda.
    var notchBottomSlot: QuotaSlot {
        get { QuotaSlot(stored: store.string(forKey: Keys.notchBottomSlot)) }
        set { store.set(newValue.stored.isEmpty ? nil : newValue.stored, forKey: Keys.notchBottomSlot) }
    }

    /// O card-herói do popover — o bloco grande em gradiente no topo.
    ///
    /// Nasceu travado na pior janela, sem escolha nenhuma: o dono não conseguia colocar
    /// outro uso no card principal, só olhar o que já era o mais crítico. Em automático
    /// continua sendo essa mesma regra (a pior janela entre TODAS, não uma por
    /// provedor); a escolha explícita é o que faltava.
    var popoverHeroSlot: QuotaSlot {
        get { QuotaSlot(stored: store.string(forKey: Keys.popoverHeroSlot)) }
        set { store.set(newValue.stored.isEmpty ? nil : newValue.stored, forKey: Keys.popoverHeroSlot) }
    }

    // MARK: - Alvo da previsão

    /// A janela usada para a previsão de uso. Sem escolha persistida, o engine decide
    /// automaticamente qual é a mais relevante.
    var forecastSlot: ForecastSlot {
        get { ForecastSlot(stored: store.string(forKey: Keys.forecastSlot)) }
        set { store.set(newValue.stored.isEmpty ? nil : newValue.stored, forKey: Keys.forecastSlot) }
    }

    // MARK: - Escala de cor do uso

    /// As paradas da escala de cor, na codificação estável do próprio tipo
    /// (`"7:F5384A,23:FF9D00,…"`). Nada gravado — ou gravado inválido — vale como o
    /// padrão ditado pelo dono: uma escala quebrada tiraria a cor do app inteiro, então
    /// o parser recusa o lixo em silêncio em vez de propagá-lo.
    var usageColorScale: UsageColorScale {
        get { UsageColorScale(encoded: store.string(forKey: Keys.usageColorScale)) ?? .standard }
        set { store.set(newValue.encoded, forKey: Keys.usageColorScale) }
    }

    // MARK: - Alert preferences

    /// Master switch for quota notifications. Defaults to enabled.
    var alertsEnabled: Bool {
        get { store.string(forKey: Keys.alertsEnabled) != "false" }
        set { store.set(newValue ? "true" : "false", forKey: Keys.alertsEnabled) }
    }

    /// Percentage crossings that trigger a notification, as fractions (0.7 = 70% usado).
    /// Persisted as a comma-joined string; unset means the historical defaults. An empty
    /// string is a deliberate "no percentage alerts" choice and round-trips as [].
    var alertPercentThresholds: [Double] {
        get {
            guard let raw = store.string(forKey: Keys.alertPercentThresholds) else {
                return [0.7, 0.9, 1.0]
            }
            return raw.split(separator: ",").compactMap { Double($0) }
        }
        set { store.set(newValue.map { String($0) }.joined(separator: ","), forKey: Keys.alertPercentThresholds) }
    }

    /// Balance (em USD) abaixo do qual providers de saldo disparam alerta.
    var alertLowBalanceThreshold: Double {
        get {
            let stored = store.double(forKey: Keys.alertLowBalanceThreshold)
            return stored > 0 ? stored : 5.0
        }
        set { store.set(newValue, forKey: Keys.alertLowBalanceThreshold) }
    }

    func refreshInterval(for providerId: String, default defaultValue: TimeInterval) -> TimeInterval {
        let stored = store.double(forKey: Keys.refreshInterval(providerId))
        return stored > 0 ? stored : defaultValue
    }

    func setRefreshInterval(_ interval: TimeInterval, for providerId: String) {
        store.set(interval, forKey: Keys.refreshInterval(providerId))
    }
}

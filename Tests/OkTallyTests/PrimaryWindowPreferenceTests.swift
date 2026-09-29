// Tests/OkTallyTests/PrimaryWindowPreferenceTests.swift
import XCTest
@testable import OkTally

/// "Qual cota é a principal DESTA conta" — a regra automática nova (a mais apertada
/// entre as GERAIS) e a escolha explícita do dono.
///
/// Nasceu de um relato concreto: a conta Business do Codex tem uma janela de 5h que
/// acaba no meio do dia e uma semanal que quase nunca aperta. A regra antiga era "Codex
/// é sempre o Weekly", então a barra principal mostrava 84% de folga enquanto a sessão
/// de 5h estava no fim — e não havia nenhum jeito de dizer ao app que ali a 5h é o que
/// importa.
final class PrimaryWindowPreferenceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // A resolução automática consulta o diretório de contas vigente; um teste
        // anterior que tenha deixado uma escolha gravada não pode vazar para cá.
        AccountDirectoryHolder.current = .empty
    }

    override func tearDown() {
        AccountDirectoryHolder.current = .empty
        super.tearDown()
    }

    private func rolling(usedPercent: Double, hours: Double = 5) -> QuotaShape {
        .rollingWindow(used: usedPercent, limit: 100, windowStart: Date(),
                       resetAt: Date().addingTimeInterval(hours * 3600))
    }

    private func window(_ label: String, remainingPercent: Double, hours: Double = 5) -> QuotaWindow {
        QuotaWindow(label: label, shape: rolling(usedPercent: 100 - remainingPercent, hours: hours))
    }

    private func snapshot(_ id: String, _ quotas: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(providerId: id, fetchedAt: Date(), quotas: quotas, usageDetail: nil)
    }

    /// A conta Business: semanal folgada, 5h geral no aperto.
    private var businessCodex: [QuotaWindow] {
        [window("weekly", remainingPercent: 84, hours: 7 * 24),
         window("5h", remainingPercent: 20)]
    }

    // MARK: - Persistência da escolha

    /// Conta gravada por uma versão anterior não tem a chave. Decodificar tem que dar
    /// "automático", não erro — senão a lista inteira de contas some no primeiro launch.
    func test_accountInstance_missingKeyDecodesAsAutomatic() throws {
        let legacy = #"{"id":"codex","kind":"codex","nickname":"OkamiOps"}"#
        let account = try JSONDecoder().decode(AccountInstance.self, from: Data(legacy.utf8))
        XCTAssertNil(account.primaryWindowLabel)
        XCTAssertEqual(account.nickname, "OkamiOps")
    }

    func test_accountInstance_primaryWindowLabelRoundTrips() throws {
        var account = AccountInstance(id: "codex#abc123", kind: .codex)
        account.primaryWindowLabel = "5h"
        let data = try JSONEncoder().encode(account)
        XCTAssertEqual(try JSONDecoder().decode(AccountInstance.self, from: data), account)
    }

    @MainActor
    func test_appModel_setPrimaryWindow_persistsOnTheAccount() {
        let suite = "oktally.tests.primary-window.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = PreferencesStore(store: defaults, secretStore: FakeSecretStore())
        let registry = PluginRegistry()
        let scheduler = Scheduler(registry: registry, storage: FakeStorage(), alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        let model = AppModel(registry: registry, scheduler: scheduler, defaults: defaults, preferences: preferences)

        model.setPrimaryWindow(providerId: "codex", windowLabel: "5h")
        XCTAssertEqual(model.primaryWindowLabel(forProviderId: "codex"), "5h")
        XCTAssertEqual(model.persistedAccounts.first { $0.id == "codex" }?.primaryWindowLabel, "5h")

        // `nil` é o caminho de volta para automático — e tem que apagar o valor gravado.
        model.setPrimaryWindow(providerId: "codex", windowLabel: nil)
        XCTAssertNil(model.primaryWindowLabel(forProviderId: "codex"))
        XCTAssertNil(model.persistedAccounts.first { $0.id == "codex" }?.primaryWindowLabel)
    }

    // MARK: - Regra automática

    /// O caso do dono: numa conta Business, o que acaba durante o dia é a sessão de 5h.
    func test_codexAutomatic_picksTightestGeneralWindow() {
        XCTAssertEqual(
            PopoverLayout.primaryWindow(providerId: "codex", quotas: businessCodex)?.label,
            "5h"
        )
    }

    /// A conta Pro só tem a semanal — ela continua sendo a principal, como sempre foi.
    func test_codexAutomatic_weeklyOnlyAccountKeepsWeekly() {
        let pro = [window("weekly", remainingPercent: 41, hours: 7 * 24)]
        XCTAssertEqual(PopoverLayout.primaryWindow(providerId: "codex", quotas: pro)?.label, "weekly")
    }

    /// Uma janela específica de modelo no fim NÃO pode sequestrar a barra principal: ela
    /// mede a capacidade de um modelo, não a do plano.
    func test_codexAutomatic_modelSpecificWindowNeverWins() {
        let quotas = [
            window("weekly", remainingPercent: 84, hours: 7 * 24),
            window("5h", remainingPercent: 55),
            window("GPT-5.3-Codex-Spark (5h)", remainingPercent: 3)
        ]
        XCTAssertEqual(PopoverLayout.primaryWindow(providerId: "codex", quotas: quotas)?.label, "5h")
        // E ela continua visível logo abaixo, no topo das secundárias (mais apertada
        // primeiro) — some da barra principal, não da tela.
        XCTAssertEqual(
            PopoverLayout.orderedWindows(quotas, providerId: "codex").map(\.label),
            ["5h", "GPT-5.3-Codex-Spark (5h)", "weekly"]
        )
    }

    // MARK: - Escolha explícita

    func test_explicitChoice_winsOverTheAutomaticRule() {
        XCTAssertEqual(
            PopoverLayout.primaryWindow(providerId: "codex", quotas: businessCodex,
                                        preferredLabel: "weekly")?.label,
            "weekly"
        )
    }

    /// Escolher uma janela específica de modelo é legítimo — a regra que a barra o
    /// impede vale só para o automático.
    func test_explicitChoice_mayBeAModelSpecificWindow() {
        let quotas = businessCodex + [window("GPT-5.3-Codex-Spark (5h)", remainingPercent: 70)]
        XCTAssertEqual(
            PopoverLayout.primaryWindow(providerId: "codex", quotas: quotas,
                                        preferredLabel: "GPT-5.3-Codex-Spark (5h)")?.label,
            "GPT-5.3-Codex-Spark (5h)"
        )
    }

    /// Escolha que sumiu do snapshot (o provedor parou de devolver aquela janela) cai
    /// para automático em silêncio — mesma regra dos slots do notch.
    func test_explicitChoice_missingFromSnapshotFallsBackToAutomatic() {
        XCTAssertEqual(
            PopoverLayout.primaryWindow(providerId: "codex", quotas: businessCodex,
                                        preferredLabel: "janela-que-nao-existe")?.label,
            "5h"
        )
    }

    /// A preferência não é uma regra do Codex: vale para qualquer conta com mais de uma
    /// janela (o Claude com 5h + semanal, por exemplo).
    func test_explicitChoice_appliesToNonCodexAccounts() {
        let claude = [window("5h", remainingPercent: 12), window("weekly", remainingPercent: 60, hours: 7 * 24)]
        XCTAssertEqual(PopoverLayout.primaryWindow(providerId: "claude", quotas: claude)?.label, "5h")
        XCTAssertEqual(
            PopoverLayout.primaryWindow(providerId: "claude", quotas: claude, preferredLabel: "weekly")?.label,
            "weekly"
        )
    }

    // MARK: - Quem mais respeita a escolha

    func test_popoverHero_honorsTheAccountChoice() {
        let snapshots = ["codex": snapshot("codex", businessCodex),
                         "claude": snapshot("claude", [window("5h", remainingPercent: 50)])]
        // Automático: a 5h do Codex (20%) é a mais apertada entre as representativas.
        let automatic = QuotaSlotResolver.popoverHero(
            slot: .automatic, snapshots: snapshots, providerOrder: ["claude", "codex"],
            preferredLabels: { _ in nil })
        XCTAssertEqual(automatic?.window.label, "5h")
        XCTAssertEqual(automatic?.providerId, "codex")

        // Com a semanal escolhida como principal do Codex, a representativa dele passa a
        // ser a semanal (84%) — e o herói vira o Claude, que agora é o mais apertado.
        let chosen = QuotaSlotResolver.popoverHero(
            slot: .automatic, snapshots: snapshots, providerOrder: ["claude", "codex"],
            preferredLabels: { $0 == "codex" ? "weekly" : nil })
        XCTAssertEqual(chosen?.providerId, "claude")
    }

    func test_notchAutomaticCandidates_honorTheAccountChoice() {
        let snapshots = ["codex": snapshot("codex", businessCodex)]
        XCTAssertEqual(
            NotchHUDModel.automaticCandidates(snapshots: snapshots, providerOrder: ["codex"],
                                              preferredLabels: { _ in nil }).map(\.window.label),
            ["5h"]
        )
        XCTAssertEqual(
            NotchHUDModel.automaticCandidates(snapshots: snapshots, providerOrder: ["codex"],
                                              preferredLabels: { _ in "weekly" }).map(\.window.label),
            ["weekly"]
        )
    }

    /// A barra de menu em automático também: era o último lugar onde um limite de modelo
    /// no fim ainda podia virar O número do dia.
    func test_menuBarAutomatic_usesTheRepresentativeWindow() {
        let snapshots = ["codex": snapshot("codex", businessCodex + [
            window("GPT-5.3-Codex-Spark (5h)", remainingPercent: 2)
        ])]
        let automatic = MenuBarLabelModel.criticalSegment(
            pins: [], snapshots: snapshots, hasAnyError: false, preferredLabels: { _ in nil })
        XCTAssertEqual(automatic.text, "20")

        let chosen = MenuBarLabelModel.criticalSegment(
            pins: [], snapshots: snapshots, hasAnyError: false, preferredLabels: { _ in "weekly" })
        XCTAssertEqual(chosen.text, "84")
    }

    /// O diretório de contas é a ponte entre a conta gravada e o código estático que
    /// desenha dentro de um `ImageRenderer` (barra de menu, notch).
    func test_accountDirectory_exposesTheChosenLabel() {
        var codex = AccountInstance(id: "codex", kind: .codex)
        codex.primaryWindowLabel = "5h"
        let directory = AccountDirectory(accounts: [codex, AccountInstance(id: "claude", kind: .claude)])
        XCTAssertEqual(directory.primaryWindowLabel(forProviderId: "codex"), "5h")
        XCTAssertNil(directory.primaryWindowLabel(forProviderId: "claude"))
        XCTAssertNil(directory.primaryWindowLabel(forProviderId: "nao-existe"))
    }

    // MARK: - Visibilidade das secundárias

    /// Com poucas janelas, TODA secundária com percentual ganha barra — o relato do dono
    /// era exatamente que a 5h virava "um textinho quase imperceptível" embaixo.
    func test_secondaryBars_everyPercentageWindowWhenThereAreFewOfThem() {
        let secondaries = [window("weekly", remainingPercent: 84, hours: 7 * 24),
                           window("GPT-5.3-Codex-Spark (5h)", remainingPercent: 70)]
        XCTAssertEqual(PopoverLayout.barredSecondaryLabels(secondaries),
                       ["weekly", "GPT-5.3-Codex-Spark (5h)"])
    }

    /// Com muitas, só as GERAIS ganham barra: seis barras empilhadas viram um gráfico de
    /// barras acidental e a linha principal deixa de dominar.
    func test_secondaryBars_onlyGeneralWindowsWhenThereAreMany() {
        let secondaries = [
            window("weekly", remainingPercent: 84, hours: 7 * 24),
            window("GPT-5.3-Codex-Spark (5h)", remainingPercent: 70),
            window("GPT-5.3-Codex-Spark (weekly)", remainingPercent: 65, hours: 7 * 24)
        ]
        XCTAssertEqual(PopoverLayout.barredSecondaryLabels(secondaries), ["weekly"])
    }

    /// Saldo em dólares não tem fração — sem barra, nem quando é a única secundária.
    func test_secondaryBars_skipWindowsWithoutAPercentage() {
        let secondaries = [QuotaWindow(label: "balance", shape: .creditBalance(remaining: 19.82, currency: "USD"))]
        XCTAssertEqual(PopoverLayout.barredSecondaryLabels(secondaries), [])
    }

    func test_modelSpecificWindows_areRecognizedByTheParenthesizedShape() {
        XCTAssertTrue(PopoverLayout.isModelSpecific(window("GPT-5.3-Codex-Spark (5h)", remainingPercent: 10)))
        XCTAssertTrue(PopoverLayout.isModelSpecific(window("GPT-5.3-Codex-Spark (weekly)", remainingPercent: 10)))
        XCTAssertFalse(PopoverLayout.isModelSpecific(window("5h", remainingPercent: 10)))
        XCTAssertFalse(PopoverLayout.isModelSpecific(window("weekly", remainingPercent: 10)))
        XCTAssertFalse(PopoverLayout.isModelSpecific(window("semanal", remainingPercent: 10)))
    }
}

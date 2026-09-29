import XCTest
@testable import OkTally

/// O rótulo da conta chega a todo lugar que mostra um provedor: alertas, pickers e o
/// notch (em versão compacta).
final class AccountLabelsAcrossUITests: XCTestCase {
    override func tearDown() {
        AccountDirectoryHolder.current = .empty
        super.tearDown()
    }

    private func twoClaudes() -> (PreferencesStore, [AccountInstance]) {
        let preferences = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        var extra = AccountInstance(id: "claude#abc123", kind: .claude); extra.nickname = "Trabalho"
        let accounts = [AccountInstance(id: "claude", kind: .claude, email: "me@home.test"), extra]
        preferences.accounts = accounts
        return (preferences, accounts)
    }

    func test_alertTitle_carriesTheAccountLabel_endToEnd() async {
        let (preferences, accounts) = twoClaudes()
        let fake = FakeUsageProvider(id: "claude#abc123", displayName: "Claude Code")
        fake.snapshotToReturn = ProviderSnapshot(providerId: "claude#abc123", fetchedAt: Date(), quotas: [
            QuotaWindow(label: "5h", shape: .rollingWindow(used: 75, limit: 100, windowStart: Date(), resetAt: Date().addingTimeInterval(3600)))
        ], usageDetail: nil)
        let registry = PluginRegistry()
        registry.register(ProviderFactory.labeled(fake, account: accounts[1], all: accounts, preferences: preferences))
        let sender = FakeNotificationSender()
        let scheduler = Scheduler(registry: registry, storage: FakeStorage(), alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: sender))

        _ = await scheduler.fetchAll()

        XCTAssertEqual(sender.sentMessages.first?.title, "Claude Code · Trabalho — 5h")
    }

    func test_slotPickerText_isAccountLabelThenWindow() {
        XCTAssertEqual(QuotaSlotLabel.text(providerName: "Claude Code · Trabalho", windowLabel: "5h"),
                       "Claude Code · Trabalho · \(WindowLabelCatalog.displayLabel("5h"))")
    }

    func test_shortLabel_nicknameOrEmailLocalPart_onlyWhenItHelps() {
        let (_, accounts) = twoClaudes()
        let dir = AccountDirectory(accounts: accounts)
        XCTAssertEqual(dir.shortLabel(for: "claude#abc123"), "Trabalho")
        XCTAssertEqual(dir.shortLabel(for: "claude"), "me")
        let single = AccountDirectory(accounts: [AccountInstance(id: "codex", kind: .codex, email: "c@x.test")])
        XCTAssertNil(single.shortLabel(for: "codex"))
    }

    func test_compactName_forTheNotch() {
        let (_, accounts) = twoClaudes()
        let dir = AccountDirectory(accounts: accounts)
        XCTAssertEqual(dir.compactName(for: "claude#abc123", baseName: "Claude Code"), "Claude Code · Trabalho")
        XCTAssertEqual(dir.compactName(for: "claude", baseName: "Claude Code"), "Claude Code · me")
        XCTAssertEqual(AccountDirectory.empty.compactName(for: "codex", baseName: "Codex"), "Codex")
    }

    /// O botão "adicionar outra conta" é o ÚNICO lugar da tela de conta que fala do
    /// TIPO e não daquela conta. Com o nome rotulado ele lia "Adicionar outra conta
    /// Codex · OkamiOps" — ou seja, prometia outra conta da OkamiOps, quando o que ele
    /// abre é um login vazio para outra pessoa.
    func test_addAnotherAccountButton_namesTheKindAndNotTheAccount() {
        let title = PreferencesView.addAnotherAccountTitle(.codex)
        XCTAssertEqual(title, LF("Adicionar outra conta %@", "Codex"))
        XCTAssertFalse(title.contains("·"), "o rótulo da conta vazou para o botão: \(title)")
        for kind in AccountKind.addableKinds {
            XCTAssertTrue(PreferencesView.addAnotherAccountTitle(kind)
                .contains(PreferencesView.kindName(kind)), kind.rawValue)
        }
    }

    func test_baseName_unwrapsLabeledProvider() {
        let labeled = LabeledProvider(base: FakeUsageProvider(id: "a", displayName: "Base"), label: { "Base · x" })
        XCTAssertEqual(AccountLabel.baseName(of: labeled), "Base")
        XCTAssertEqual(AccountLabel.baseName(of: FakeUsageProvider(id: "b", displayName: "Plain")), "Plain")
    }
}

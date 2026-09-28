import XCTest
@testable import OkTally

final class ProviderFactoryTests: XCTestCase {
    private func makeFactory(accounts: [AccountInstance]? = nil) -> ProviderFactory {
        let preferences = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        if let accounts { preferences.accounts = accounts }
        return ProviderFactory(dependencies: .testing(tokenStore: InMemoryTokenStore(), preferences: preferences))
    }

    private func allProviders(_ factory: ProviderFactory, accounts: [AccountInstance]) -> [UsageProvider] {
        accounts.flatMap { factory.providers(for: $0, all: accounts) }
    }

    func test_defaults_produceTodaysRegistryIdsInOrder() {
        let ids = allProviders(makeFactory(), accounts: AccountsCatalog.defaultAccounts).map(\.id)
        XCTAssertEqual(ids, ["claude", "codex", "openrouter", "minimax", "cursor", "cursor-grokbot",
                             "copilot", "antigravity", "opencode", "mimo", "supergrok"])
    }

    func test_defaults_keepTodaysDisplayNames() {
        let names = allProviders(makeFactory(), accounts: AccountsCatalog.defaultAccounts).map(\.displayName)
        XCTAssertEqual(names, ["Claude Code", "Codex", "OpenRouter", "MiniMax", "Cursor", "GrokBot",
                               "GitHub Copilot", "Antigravity", "OpenCode", "MiMo", "SuperGrok"])
    }

    func test_extraCursor_emitsGrokBotTwin() {
        let extra = AccountInstance(id: "cursor#abc123", kind: .cursor)
        XCTAssertEqual(makeFactory().providers(for: extra, all: [extra]).map(\.id), ["cursor#abc123", "cursor-grokbot#abc123"])
    }

    func test_extraClaude_isKeyedByInstanceId() {
        let extra = AccountInstance(id: "claude#abc123", kind: .claude)
        XCTAssertEqual(makeFactory().providers(for: extra, all: [extra]).map(\.id), ["claude#abc123"])
    }

    func test_label_followsCurrentAccountsFromPreferences() {
        var legacy = AccountInstance(id: "claude", kind: .claude)
        let extra = AccountInstance(id: "claude#abc123", kind: .claude)
        let preferences = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        preferences.accounts = [legacy, extra]
        let factory = ProviderFactory(dependencies: .testing(tokenStore: InMemoryTokenStore(), preferences: preferences))
        let provider = factory.providers(for: extra, all: [legacy, extra])[0]
        XCTAssertEqual(provider.displayName, "Claude Code · 2")

        legacy.nickname = "Pessoal"
        var renamed = extra; renamed.nickname = "Trabalho"
        preferences.accounts = [legacy, renamed]
        XCTAssertEqual(provider.displayName, "Claude Code · Trabalho")
    }

    func test_grokBotTwin_labelFollowsItsCursorAccount() {
        var cursor = AccountInstance(id: "cursor#abc123", kind: .cursor); cursor.nickname = "Trabalho"
        let factory = makeFactory(accounts: [AccountInstance(id: "cursor", kind: .cursor), cursor])
        let twin = factory.providers(for: cursor, all: [cursor])[1]
        XCTAssertEqual(twin.displayName, "GrokBot · Trabalho")
    }

    func test_labeledProvider_forwardsEverythingButDisplayName() async throws {
        let base = FakeUsageProvider(id: "a", displayName: "A")
        base.snapshotToReturn = ProviderSnapshot(providerId: "a", fetchedAt: Date(), quotas: [], usageDetail: nil)
        let labeled = LabeledProvider(base: base, label: { "A · x" })
        XCTAssertEqual(labeled.id, "a")
        XCTAssertEqual(labeled.displayName, "A · x")
        XCTAssertEqual(labeled.refreshInterval, 60)
        let authenticated = await labeled.isAuthenticated()
        XCTAssertTrue(authenticated)
        let snapshot = try await labeled.fetchSnapshot()
        XCTAssertEqual(snapshot.providerId, "a")
    }

    func test_registry_replaceAddRemove() {
        let registry = PluginRegistry()
        registry.register(FakeUsageProvider(id: "a", displayName: "A"))
        registry.add([FakeUsageProvider(id: "b", displayName: "B")])
        registry.remove(ids: ["a"])
        XCTAssertEqual(registry.providers.map(\.id), ["b"])
    }

    func test_extraOpenRouter_readsItsOwnKey() async throws {
        let preferences = PreferencesStore(store: FakeKeyValueStore(), secretStore: FakeSecretStore())
        try preferences.setAPIKey("sk-extra", instanceId: "openrouter#abc123")
        let factory = ProviderFactory(dependencies: .testing(tokenStore: InMemoryTokenStore(), preferences: preferences))
        let extra = AccountInstance(id: "openrouter#abc123", kind: .openrouter)
        let legacy = factory.providers(for: AccountInstance(id: "openrouter", kind: .openrouter), all: [extra])[0]
        let provider = factory.providers(for: extra, all: [extra])[0]
        let extraAuthenticated = await provider.isAuthenticated()
        let legacyAuthenticated = await legacy.isAuthenticated()
        XCTAssertTrue(extraAuthenticated)
        XCTAssertFalse(legacyAuthenticated)
    }
}

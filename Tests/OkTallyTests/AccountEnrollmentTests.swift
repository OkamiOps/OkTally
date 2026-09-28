import XCTest
@testable import OkTally

@MainActor
final class AccountEnrollmentTests: XCTestCase {
    /// Resolver falso: devolve o que o teste mandar.
    final class FakeResolver {
        var next = AccountIdentity()
    }

    /// Modelo com as contas legadas mais `existing`, provedores falsos e o Keychain em
    /// memória — o suficiente para exercitar o commit e a recusa por duplicata.
    struct EnrollmentEnv {
        let model: AppModel
        let tokens: InMemoryTokenStore
        let resolver: FakeResolver
        let enrollment: AccountEnrollment

        @MainActor init(existing: [AccountInstance]) {
            let suite = "oktally.tests.enrollment.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let preferences = PreferencesStore(store: defaults, secretStore: FakeSecretStore())
            let existingIds = Set(existing.map(\.id))
            preferences.accounts = AccountsCatalog.defaultAccounts.filter { !existingIds.contains($0.id) } + existing
            let registry = PluginRegistry()
            let factory: (AccountInstance) -> [UsageProvider] = { account in
                let fake = FakeUsageProvider(id: account.id, displayName: account.kind.rawValue)
                fake.isAuthenticatedResult = false
                return [fake]
            }
            for account in preferences.accounts { factory(account).forEach(registry.register) }
            let scheduler = Scheduler(registry: registry, storage: FakeStorage(), alertEngine: AlertEngine(),
                                      alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
            let model = AppModel(registry: registry, scheduler: scheduler, defaults: defaults, preferences: preferences)
            let tokens = InMemoryTokenStore()
            let resolver = FakeResolver()
            model.providerFactory = factory
            model.credentialEraser = { try tokens.delete(providerId: $0.id) }
            model.identityResolver = { _ in resolver.next }
            self.model = model
            self.tokens = tokens
            self.resolver = resolver
            self.enrollment = AccountEnrollment(model: model)
        }
    }

    func test_beginDraft_reusesLegacyIdOnlyWhenFree() {
        let env = EnrollmentEnv(existing: [])
        XCTAssertTrue(env.enrollment.beginDraft(kind: .claude).hasPrefix("claude#"))
        try? env.model.removeAccount(id: "codex")
        XCTAssertEqual(env.enrollment.beginDraft(kind: .codex), "codex")
    }

    func test_enroll_commitsWhenIdentityIsNew() async throws {
        let env = EnrollmentEnv(existing: [AccountInstance(id: "claude", kind: .claude, identityKey: "a@x.com")])
        env.resolver.next = AccountIdentity(email: "b@x.com", identityKey: "b@x.com")
        let result = await env.enrollment.finish(draftId: "claude#abc123", kind: .claude)
        XCTAssertEqual(result, .committed)
        XCTAssertEqual(env.model.accounts.last?.id, "claude#abc123")
        XCTAssertEqual(env.model.accounts.last?.email, "b@x.com")
        XCTAssertEqual(env.model.accounts.last?.identityKey, "b@x.com")
    }

    func test_enroll_duplicateIsRefusedAndCredentialDeleted() async throws {
        let env = EnrollmentEnv(existing: [AccountInstance(id: "claude", kind: .claude, identityKey: "a@x.com")])
        try env.tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "claude#abc123")
        env.resolver.next = AccountIdentity(email: "A@x.com", identityKey: "a@x.com")
        let result = await env.enrollment.finish(draftId: "claude#abc123", kind: .claude)
        XCTAssertEqual(result, .duplicate(email: "A@x.com"))
        XCTAssertNil(env.tokens.load(providerId: "claude#abc123"))
        XCTAssertFalse(env.model.accounts.contains { $0.id == "claude#abc123" })
    }

    /// Decisão do dono: mesma pessoa em outra org do Claude continua sendo a mesma conta.
    func test_enroll_claudeSameEmailOtherOrg_isStillDuplicate() async {
        let env = EnrollmentEnv(existing: [AccountInstance(id: "claude", kind: .claude, email: "a@x.com", identityKey: "a@x.com")])
        env.resolver.next = AccountIdentity(email: "a@x.com", identityKey: "a@x.com")
        let result = await env.enrollment.finish(draftId: "claude#abc123", kind: .claude)
        XCTAssertEqual(result, .duplicate(email: "a@x.com"))
    }

    func test_enroll_unresolvableIdentity_commitsWithoutEmail() async {
        let env = EnrollmentEnv(existing: [])
        env.resolver.next = AccountIdentity()
        let result = await env.enrollment.finish(draftId: "codex#abc123", kind: .codex)
        XCTAssertEqual(result, .committed)
        XCTAssertNil(env.model.accounts.last?.email)
    }

    func test_enroll_alreadyCommittedDraft_fails() async {
        let env = EnrollmentEnv(existing: [])
        let result = await env.enrollment.finish(draftId: "codex", kind: .codex)
        XCTAssertEqual(result, .failed)
    }

    func test_abandon_erasesDraftCredential() throws {
        let env = EnrollmentEnv(existing: [])
        try env.tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "codex#abc123")
        env.enrollment.abandon(draftId: "codex#abc123", kind: .codex)
        XCTAssertNil(env.tokens.load(providerId: "codex#abc123"))
    }

    func test_abandon_neverTouchesACommittedAccount() throws {
        let env = EnrollmentEnv(existing: [])
        try env.tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "codex")
        env.enrollment.abandon(draftId: "codex", kind: .codex)
        XCTAssertNotNil(env.tokens.load(providerId: "codex"))
    }

    func test_enroll_apiKeyAccount_sameKeyIsDuplicate_newKeyStoresAutoLabel() async {
        let fingerprint = AccountDedup.fingerprint(apiKey: "sk-or-1")
        let env = EnrollmentEnv(existing: [AccountInstance(id: "openrouter", kind: .openrouter, identityKey: fingerprint)])
        env.resolver.next = AccountIdentity(email: nil, identityKey: fingerprint, autoLabel: "sk-or-v1-aaa...111")
        let duplicate = await env.enrollment.finish(draftId: "openrouter#abc123", kind: .openrouter)
        XCTAssertEqual(duplicate, .duplicate(email: nil))

        env.resolver.next = AccountIdentity(email: nil, identityKey: AccountDedup.fingerprint(apiKey: "sk-or-2"), autoLabel: "Trabalho key")
        let committed = await env.enrollment.finish(draftId: "openrouter#abc123", kind: .openrouter)
        XCTAssertEqual(committed, .committed)
        XCTAssertEqual(env.model.accounts.last?.autoLabel, "Trabalho key")
    }

    // MARK: - Revisão: credencial só grava para conta viva ou rascunho ativo

    func test_acceptsCredential_onlyForCommittedAccountOrActiveDraft() throws {
        let env = EnrollmentEnv(existing: [])
        XCTAssertTrue(env.enrollment.acceptsCredential(for: "openrouter"))
        try env.model.removeAccount(id: "openrouter")
        // O painel da conta removida some e o auto-save dispara no onDisappear: não pode
        // regravar a chave morta.
        XCTAssertFalse(env.enrollment.acceptsCredential(for: "openrouter"))

        let draft = env.enrollment.beginDraft(kind: .openrouter)
        XCTAssertEqual(draft, "openrouter")
        XCTAssertTrue(env.enrollment.acceptsCredential(for: draft))
        env.enrollment.abandon(draftId: draft, kind: .openrouter)
        XCTAssertFalse(env.enrollment.acceptsCredential(for: draft))
    }
}

import XCTest
@testable import OkTally

@MainActor
final class AccountEnrollmentTests: XCTestCase {
    /// Resolver falso: devolve o que o teste mandar.
    final class FakeResolver {
        var next = AccountIdentity()
        /// Roda no meio da resolução — simula o dono clicando "Cancelar" durante o await.
        var onResolve: (@MainActor () -> Void)?
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
            model.identityResolver = { _ in
                await resolver.onResolve?()
                return resolver.next
            }
            self.model = model
            self.tokens = tokens
            self.resolver = resolver
            self.enrollment = AccountEnrollment(model: model)
        }

        /// Marca `id` como o rascunho ativo (o que `beginDraft` faz com um id sorteado).
        @MainActor func activate(_ id: String) {
            model.activeDraftId = id
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
        env.activate("claude#abc123")
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
        env.activate("claude#abc123")
        let result = await env.enrollment.finish(draftId: "claude#abc123", kind: .claude)
        XCTAssertEqual(result, .duplicate(email: "A@x.com"))
        XCTAssertNil(env.tokens.load(providerId: "claude#abc123"))
        XCTAssertFalse(env.model.accounts.contains { $0.id == "claude#abc123" })
    }

    /// Decisão do dono: mesma pessoa em outra org do Claude continua sendo a mesma conta.
    func test_enroll_claudeSameEmailOtherOrg_isStillDuplicate() async {
        let env = EnrollmentEnv(existing: [AccountInstance(id: "claude", kind: .claude, email: "a@x.com", identityKey: "a@x.com")])
        env.resolver.next = AccountIdentity(email: "a@x.com", identityKey: "a@x.com")
        env.activate("claude#abc123")
        let result = await env.enrollment.finish(draftId: "claude#abc123", kind: .claude)
        XCTAssertEqual(result, .duplicate(email: "a@x.com"))
    }

    func test_enroll_unresolvableIdentity_commitsWithoutEmail() async {
        let env = EnrollmentEnv(existing: [])
        env.resolver.next = AccountIdentity()
        env.activate("codex#abc123")
        let result = await env.enrollment.finish(draftId: "codex#abc123", kind: .codex)
        XCTAssertEqual(result, .committed)
        XCTAssertNil(env.model.accounts.last?.email)
    }

    func test_enroll_alreadyCommittedDraft_fails() async {
        let env = EnrollmentEnv(existing: [])
        env.activate("codex")
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
        env.activate("openrouter#abc123")
        let duplicate = await env.enrollment.finish(draftId: "openrouter#abc123", kind: .openrouter)
        XCTAssertEqual(duplicate, .duplicate(email: nil))

        env.resolver.next = AccountIdentity(email: nil, identityKey: AccountDedup.fingerprint(apiKey: "sk-or-2"), autoLabel: "Trabalho key")
        env.activate("openrouter#abc123")
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

    // MARK: - Revisão: cancelar durante "Identificando a conta…"

    func test_finish_draftCancelledDuringIdentityLookup_doesNotCommitAndErasesCredential() async throws {
        let env = EnrollmentEnv(existing: [])
        let draft = env.enrollment.beginDraft(kind: .claude)
        try env.tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: draft)
        env.resolver.next = AccountIdentity(email: "new@x.com", identityKey: "new@x.com")
        env.resolver.onResolve = { env.enrollment.abandon(draftId: draft, kind: .claude) }

        let result = await env.enrollment.finish(draftId: draft, kind: .claude)

        XCTAssertEqual(result, .cancelled)
        XCTAssertFalse(env.model.accounts.contains { $0.id == draft })
        XCTAssertNil(env.tokens.load(providerId: draft))
    }

    func test_finish_notTheActiveDraft_isCancelled() async {
        let env = EnrollmentEnv(existing: [])
        env.resolver.next = AccountIdentity(email: "n@x.com", identityKey: "n@x.com")
        let result = await env.enrollment.finish(draftId: "codex#dead00", kind: .codex)
        XCTAssertEqual(result, .cancelled)
        XCTAssertFalse(env.model.accounts.contains { $0.id == "codex#dead00" })
    }

    func test_finish_commit_clearsActiveDraft() async {
        let env = EnrollmentEnv(existing: [])
        let draft = env.enrollment.beginDraft(kind: .codex)
        let result = await env.enrollment.finish(draftId: draft, kind: .codex)
        XCTAssertEqual(result, .committed)
        XCTAssertNil(env.model.activeDraftId)
    }

    // MARK: - Revisão: login que termina depois de o rascunho ter sido trocado

    func test_loginCompleted_forAbandonedDraft_erasesTheOrphanToken() throws {
        let env = EnrollmentEnv(existing: [])
        let first = env.enrollment.beginDraft(kind: .claude)
        env.enrollment.abandon(draftId: first, kind: .claude)
        _ = env.enrollment.beginDraft(kind: .codex) // o dono trocou de tipo
        // O fluxo do primeiro rascunho termina agora e grava o token dele.
        try env.tokens.save(OAuthToken(accessToken: "late", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: first)

        XCTAssertEqual(env.enrollment.loginCompleted(id: first), .orphaned)
        XCTAssertNil(env.tokens.load(providerId: first))
    }

    func test_loginCompleted_forActiveDraftOrAccount_keepsTheToken() throws {
        let env = EnrollmentEnv(existing: [])
        let draft = env.enrollment.beginDraft(kind: .codex)
        try env.tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: draft)
        try env.tokens.save(OAuthToken(accessToken: "t", refreshToken: nil, expiresAt: nil, extra: [:]), providerId: "claude")
        XCTAssertEqual(env.enrollment.loginCompleted(id: draft), .activeDraft)
        XCTAssertEqual(env.enrollment.loginCompleted(id: "claude"), .existingAccount)
        XCTAssertNotNil(env.tokens.load(providerId: draft))
        XCTAssertNotNil(env.tokens.load(providerId: "claude"))
    }
}

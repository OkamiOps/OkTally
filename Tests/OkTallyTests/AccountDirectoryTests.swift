import XCTest
@testable import OkTally

final class AccountDirectoryTests: XCTestCase {
    override func tearDown() {
        AccountDirectoryHolder.current = .empty
        super.tearDown()
    }

    private let twoClaudes = AccountDirectory(accounts: [AccountInstance(id: "claude", kind: .claude),
                                                         AccountInstance(id: "claude#abc123", kind: .claude)])

    func test_glyph_secondSiblingGetsOrdinal() {
        XCTAssertEqual(twoClaudes.glyph(for: "claude"), "C")
        XCTAssertEqual(twoClaudes.glyph(for: "claude#abc123"), "C2")
    }

    func test_glyph_singleAccountsAreUnchanged() {
        let dir = AccountDirectory(accounts: AccountsCatalog.defaultAccounts)
        for id in ["claude", "codex", "cursor", "cursor-grokbot", "openrouter", "mimo"] {
            XCTAssertEqual(dir.glyph(for: id), AccountDirectory.empty.glyph(for: id), id)
        }
    }

    func test_glyph_grokBotTwinFollowsItsCursorOrdinal() {
        let dir = AccountDirectory(accounts: [AccountInstance(id: "cursor", kind: .cursor),
                                              AccountInstance(id: "cursor#abc123", kind: .cursor)])
        XCTAssertEqual(dir.glyph(for: "cursor-grokbot"), "GB")
        XCTAssertEqual(dir.glyph(for: "cursor-grokbot#abc123"), "GB2")
    }

    func test_paletteGlyph_consultsTheHolder() {
        XCTAssertEqual(ProviderPalette.glyph(forId: "claude#abc123"), "C")
        AccountDirectoryHolder.current = twoClaudes
        XCTAssertEqual(ProviderPalette.glyph(forId: "claude#abc123"), "C2")
    }

    func test_menuBarSegment_usesDirectoryGlyph() {
        AccountDirectoryHolder.current = twoClaudes
        let shape = QuotaShape.rollingWindow(used: 50, limit: 100, windowStart: Date(), resetAt: Date().addingTimeInterval(3600))
        XCTAssertEqual(MenuBarLabelModel.segment(providerId: "claude#abc123", shape: shape).glyph, "C2")
        XCTAssertEqual(MenuBarLabelModel.segment(providerId: "claude", shape: shape).glyph, "C")
    }

    @MainActor
    func test_appModel_publishesDirectoryWhenAccountsChange() throws {
        let suite = "oktally.tests.directory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = PreferencesStore(store: defaults, secretStore: FakeSecretStore())
        let registry = PluginRegistry()
        let scheduler = Scheduler(registry: registry, storage: FakeStorage(), alertEngine: AlertEngine(),
                                  alertDispatcher: AlertDispatcher(sender: FakeNotificationSender()))
        let model = AppModel(registry: registry, scheduler: scheduler, defaults: defaults, preferences: preferences)
        model.providerFactory = { _ in [] }
        model.commitAccount(AccountInstance(id: "codex#abc123", kind: .codex))
        XCTAssertEqual(ProviderPalette.glyph(forId: "codex#abc123"), "X2")
        try model.removeAccount(id: "codex#abc123")
        XCTAssertEqual(ProviderPalette.glyph(forId: "codex#abc123"), "X")
    }
}

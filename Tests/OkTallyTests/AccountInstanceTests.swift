import XCTest
@testable import OkTally

final class AccountInstanceTests: XCTestCase {
    func test_defaults_matchTodaysRegistrationOrderWithoutGrokBot() {
        XCTAssertEqual(AccountsCatalog.defaultAccounts.map(\.id),
                       ["claude", "codex", "openrouter", "minimax", "cursor", "copilot",
                        "antigravity", "opencode", "mimo", "supergrok"])
    }

    func test_label_singleAccountWithoutNickname_isKindDisplayName() {
        let a = AccountInstance(id: "claude", kind: .claude)
        XCTAssertEqual(AccountLabel.display(for: a, baseName: "Claude Code", siblings: [a]), "Claude Code")
    }

    func test_label_nicknameAlwaysShows() {
        var a = AccountInstance(id: "claude", kind: .claude); a.nickname = "Trabalho"
        XCTAssertEqual(AccountLabel.display(for: a, baseName: "Claude Code", siblings: [a]), "Claude Code · Trabalho")
    }

    func test_label_siblingsWithoutNickname_fallBackToEmailThenOrdinal() {
        var a = AccountInstance(id: "claude", kind: .claude); a.email = "me@work.com"
        let b = AccountInstance(id: "claude#abc123", kind: .claude)
        XCTAssertEqual(AccountLabel.display(for: a, baseName: "Claude Code", siblings: [a, b]), "Claude Code · me@work.com")
        XCTAssertEqual(AccountLabel.display(for: b, baseName: "Claude Code", siblings: [a, b]), "Claude Code · 2")
    }

    func test_label_siblingsOfOtherKindsDoNotCount() {
        let a = AccountInstance(id: "claude", kind: .claude)
        let b = AccountInstance(id: "codex", kind: .codex)
        XCTAssertEqual(AccountLabel.display(for: a, baseName: "Claude Code", siblings: [a, b]), "Claude Code")
    }

    func test_dedup_sameKindSameIdentity_isDuplicate() {
        var a = AccountInstance(id: "codex", kind: .codex); a.identityKey = "me@x.com"
        XCTAssertTrue(AccountDedup.isDuplicate(identityKey: "ME@x.com", kind: .codex, among: [a], excluding: "codex#new000"))
        XCTAssertFalse(AccountDedup.isDuplicate(identityKey: "me@x.com", kind: .claude, among: [a], excluding: "claude#new000"))
        XCTAssertFalse(AccountDedup.isDuplicate(identityKey: nil, kind: .codex, among: [a], excluding: "codex#new000"))
    }

    func test_dedup_ignoresTheExcludedInstanceItself() {
        var a = AccountInstance(id: "codex", kind: .codex); a.identityKey = "me@x.com"
        XCTAssertFalse(AccountDedup.isDuplicate(identityKey: "me@x.com", kind: .codex, among: [a], excluding: "codex"))
    }

    func test_codableRoundTrip() throws {
        var a = AccountInstance(id: "claude#abc123", kind: .claude)
        a.nickname = "Pessoal"; a.email = "p@x.com"; a.identityKey = "p@x.com"
        let data = try JSONEncoder().encode([a])
        XCTAssertEqual(try JSONDecoder().decode([AccountInstance].self, from: data), [a])
    }
}

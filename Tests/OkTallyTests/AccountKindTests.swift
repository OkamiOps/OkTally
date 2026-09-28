import XCTest
@testable import OkTally

final class AccountKindTests: XCTestCase {
    func test_kind_legacyIdIsItsOwnKind() {
        XCTAssertEqual(AccountID.kind(of: "claude"), .claude)
        XCTAssertEqual(AccountID.kind(of: "cursor-grokbot"), .grokbot)
    }

    func test_kind_extraInstanceParsesPrefixBeforeHash() {
        XCTAssertEqual(AccountID.kind(of: "claude#a1b2c3"), .claude)
        XCTAssertEqual(AccountID.kind(of: "cursor-grokbot#a1b2c3"), .grokbot)
    }

    func test_kind_unknownIsNil() {
        XCTAssertNil(AccountID.kind(of: "ghost"))
        XCTAssertNil(AccountID.kind(of: "ghost#123456"))
    }

    func test_isLegacy() {
        XCTAssertTrue(AccountID.isLegacy("codex"))
        XCTAssertFalse(AccountID.isLegacy("codex#00ff00"))
    }

    func test_make_usesSixHexSuffix() {
        let id = AccountID.make(kind: .codex, suffix: "abc123")
        XCTAssertEqual(id, "codex#abc123")
        let random = AccountID.make(kind: .codex)
        XCTAssertTrue(random.range(of: "^codex#[0-9a-f]{6}$", options: .regularExpression) != nil)
    }

    func test_nextId_reusesLegacyWhenFree() {
        XCTAssertEqual(AccountID.nextId(kind: .claude, existing: [], suffix: "aaaaaa"), "claude")
        XCTAssertEqual(AccountID.nextId(kind: .claude, existing: ["claude"], suffix: "aaaaaa"), "claude#aaaaaa")
    }

    func test_grokBotTwin() {
        XCTAssertEqual(AccountID.grokBotId(forCursor: "cursor"), "cursor-grokbot")
        XCTAssertEqual(AccountID.grokBotId(forCursor: "cursor#abc123"), "cursor-grokbot#abc123")
    }

    func test_separatorNeverCollidesWithPersistenceSeparators() {
        let id = AccountID.make(kind: .claude)
        XCTAssertFalse(id.contains("\u{1}"))
        XCTAssertFalse(id.contains("\u{2}"))
        XCTAssertEqual(AppModel.MenuBarPin(stored: AppModel.MenuBarPin(providerId: id, windowLabel: "5h").stored)?.providerId, id)
        XCTAssertEqual(QuotaSlot(stored: QuotaSlot.window(providerId: id, windowLabel: "weekly").stored),
                       .window(providerId: id, windowLabel: "weekly"))
    }

    func test_addableKinds_matchTheOwnersDecisions() {
        for kind in [AccountKind.claude, .codex, .supergrok, .openrouter, .minimax, .antigravity] {
            XCTAssertTrue(AccountKind.addableKinds.contains(kind), "\(kind)")
        }
        // Decisão do dono: OpenCode e MiMo ficam com uma conta só.
        XCTAssertFalse(AccountKind.addableKinds.contains(.opencode))
        XCTAssertFalse(AccountKind.addableKinds.contains(.mimo))
        XCTAssertFalse(AccountKind.addableKinds.contains(.copilot))
        XCTAssertFalse(AccountKind.addableKinds.contains(.grokbot))
    }
}

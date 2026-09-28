import XCTest
@testable import OkTally

final class AccountRemovalTests: XCTestCase {
    func test_cleanup_dropsPinsSlotsAndOrderForRemovedIdOnly() {
        let pins = [AppModel.MenuBarPin(providerId: "claude#abc123", windowLabel: "5h"),
                    AppModel.MenuBarPin(providerId: "claude", windowLabel: "5h")]
        let result = AccountRemoval.cleanup(
            removedIds: ["claude#abc123"], pins: pins,
            slots: [.window(providerId: "claude#abc123", windowLabel: "5h"), .automatic],
            order: ["claude", "claude#abc123", "codex"])
        XCTAssertEqual(result.pins.map(\.providerId), ["claude"])
        XCTAssertEqual(result.slots, [.automatic, .automatic])
        XCTAssertEqual(result.order, ["claude", "codex"])
    }

    func test_cleanup_keepsSlotsOfOtherAccounts() {
        let result = AccountRemoval.cleanup(
            removedIds: ["codex#abc123"], pins: [],
            slots: [.window(providerId: "claude", windowLabel: "5h")],
            order: [])
        XCTAssertEqual(result.slots, [.window(providerId: "claude", windowLabel: "5h")])
        XCTAssertEqual(result.order, [])
    }

    func test_canRemove_rules() {
        XCTAssertFalse(AccountRemoval.canRemove("cursor"))
        XCTAssertFalse(AccountRemoval.canRemove("antigravity"))
        XCTAssertFalse(AccountRemoval.canRemove("copilot"))
        XCTAssertFalse(AccountRemoval.canRemove("mimo"))
        XCTAssertTrue(AccountRemoval.canRemove("claude"))
        XCTAssertTrue(AccountRemoval.canRemove("openrouter"))
        XCTAssertTrue(AccountRemoval.canRemove("cursor#abc123"))
        XCTAssertFalse(AccountRemoval.canRemove("cursor-grokbot#abc123")) // segue o Cursor dele
        XCTAssertFalse(AccountRemoval.canRemove("ghost"))
    }

    /// Só sai o que pode voltar: OpenCode não aceita conta nova (decisão do dono), então a
    /// legada não pode ser removida — senão sumiria para sempre.
    func test_canRemove_legacyOfNonAddableKindIsRefused() {
        XCTAssertFalse(AccountKind.addableKinds.contains(.opencode))
        XCTAssertFalse(AccountRemoval.canRemove("opencode"))
        for kind in AccountKind.addableKinds where !kind.legacyIsMachineBound {
            XCTAssertTrue(AccountRemoval.canRemove(kind.rawValue), kind.rawValue)
        }
    }
}

import XCTest
@testable import OkTally

final class AccountPaneRoutingTests: XCTestCase {
    func test_route_dispatchesByKind() {
        XCTAssertEqual(AccountPaneRouting.route(for: "claude#abc123"), .claude(instanceId: "claude#abc123"))
        XCTAssertEqual(AccountPaneRouting.route(for: "claude"), .claude(instanceId: "claude"))
        XCTAssertEqual(AccountPaneRouting.route(for: "cursor-grokbot#abc123"), .grokbot(instanceId: "cursor-grokbot#abc123"))
        XCTAssertEqual(AccountPaneRouting.route(for: "openrouter#abc123"), .apiKey(instanceId: "openrouter#abc123", kind: .openrouter))
        XCTAssertEqual(AccountPaneRouting.route(for: "opencode"), .apiKey(instanceId: "opencode", kind: .opencode))
        XCTAssertEqual(AccountPaneRouting.route(for: "minimax"), .minimax(instanceId: "minimax"))
        XCTAssertEqual(AccountPaneRouting.route(for: "mimo"), .mimo)
        XCTAssertEqual(AccountPaneRouting.route(for: "ghost"), .unknown)
    }

    func test_canRemove() {
        XCTAssertFalse(AccountPaneRouting.canRemove("cursor"))
        XCTAssertTrue(AccountPaneRouting.canRemove("claude"))
        XCTAssertTrue(AccountPaneRouting.canRemove("cursor#abc123"))
        XCTAssertFalse(AccountPaneRouting.canRemove("cursor-grokbot#abc123")) // segue o Cursor dele
    }

    func test_accountId_grokBotPointsToItsCursorAccount() {
        XCTAssertEqual(AccountPaneRouting.accountId(forProviderId: "cursor-grokbot#abc123"), "cursor#abc123")
        XCTAssertEqual(AccountPaneRouting.accountId(forProviderId: "cursor-grokbot"), "cursor")
        XCTAssertEqual(AccountPaneRouting.accountId(forProviderId: "claude#abc123"), "claude#abc123")
    }

    func test_showsAccountSection_onlyForRenameableAccounts() {
        XCTAssertTrue(AccountPaneRouting.showsAccountSection("claude"))
        XCTAssertTrue(AccountPaneRouting.showsAccountSection("cursor"))
        XCTAssertFalse(AccountPaneRouting.showsAccountSection("cursor-grokbot"))
    }
}

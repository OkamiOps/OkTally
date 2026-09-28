import XCTest
@testable import OkTally

final class RefreshStaggerTests: XCTestCase {
    func test_singleInstancesStartImmediately() {
        let offsets = RefreshStagger.offsets(for: [("claude", 300), ("codex", 300)])
        XCTAssertEqual(offsets["claude"], 0); XCTAssertEqual(offsets["codex"], 0)
    }

    func test_siblingsSpreadAcrossInterval_cappedAt60s() {
        let offsets = RefreshStagger.offsets(for: [("claude", 300), ("claude#aaaaaa", 300), ("claude#bbbbbb", 300)])
        XCTAssertEqual(offsets["claude"], 0)
        XCTAssertEqual(offsets["claude#aaaaaa"], 60)
        XCTAssertEqual(offsets["claude#bbbbbb"], 120)
    }

    func test_siblingsWithShortInterval_splitTheInterval() {
        let offsets = RefreshStagger.offsets(for: [("codex", 60), ("codex#aaaaaa", 60)])
        XCTAssertEqual(offsets["codex#aaaaaa"], 30)
    }

    func test_defaults_allStartImmediately() {
        let input = ["claude", "codex", "openrouter", "minimax", "cursor", "cursor-grokbot",
                     "copilot", "antigravity", "opencode", "mimo", "supergrok"].map { ($0, 300.0) }
        XCTAssertTrue(RefreshStagger.offsets(for: input).values.allSatisfy { $0 == 0 })
    }

    func test_offset_forNewSibling() {
        XCTAssertEqual(RefreshStagger.offset(of: "claude#aaaaaa", among: [("claude", 300), ("claude#aaaaaa", 300)]), 60)
        XCTAssertEqual(RefreshStagger.offset(of: "ghost", among: []), 0)
    }
}

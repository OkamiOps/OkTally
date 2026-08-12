// Tests/OkTallyTests/PlanLabelTests.swift
import XCTest
@testable import OkTally

final class PlanLabelTests: XCTestCase {
    func test_cursorPlanDisplayName() {
        XCTAssertEqual(CursorUsageProvider.planDisplayName("pro"), "Pro")
        XCTAssertEqual(CursorUsageProvider.planDisplayName("free"), "Free")
        XCTAssertEqual(CursorUsageProvider.planDisplayName("pro_student"), "Pro Student")
    }

    func test_claudeProfilePlanLabel_mapsKnownTiers() {
        func profile(_ type: String?) -> [String: Any] {
            guard let type else { return [:] }
            return ["organization": ["organization_type": type]]
        }
        XCTAssertEqual(ClaudeProfileClient.planLabel(fromProfile: profile("claude_pro")), "Pro")
        XCTAssertEqual(ClaudeProfileClient.planLabel(fromProfile: profile("claude_max")), "Max")
        XCTAssertEqual(ClaudeProfileClient.planLabel(fromProfile: profile("claude_team")), "Team")
        XCTAssertEqual(ClaudeProfileClient.planLabel(fromProfile: profile("claude_enterprise")), "Enterprise")
        // Tiers desconhecidos e payloads sem organização não viram badge.
        XCTAssertNil(ClaudeProfileClient.planLabel(fromProfile: profile("something_new")))
        XCTAssertNil(ClaudeProfileClient.planLabel(fromProfile: [:]))
    }
}

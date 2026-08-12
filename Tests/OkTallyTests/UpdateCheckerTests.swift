// Tests/OkTallyTests/UpdateCheckerTests.swift
import XCTest
@testable import OkTally

final class UpdateCheckerTests: XCTestCase {
    func test_isNewer_basicSemverComparison() {
        XCTAssertTrue(UpdateChecker.isNewer(remoteTag: "v1.0.0", than: "0.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer(remoteTag: "v0.10.0", than: "0.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer(remoteTag: "v0.9.0", than: "0.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer(remoteTag: "v0.8.0", than: "0.9.0"))
    }

    func test_isNewer_ignoresVPrefixAndPrereleaseSuffix() {
        XCTAssertFalse(UpdateChecker.isNewer(remoteTag: "v0.9.0-beta", than: "0.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer(remoteTag: "v0.9.1-beta", than: "0.9.0"))
    }

    func test_isNewer_differentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer(remoteTag: "v0.9.0.1", than: "0.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer(remoteTag: "v0.9", than: "0.9.0"))
    }

    func test_isNewer_garbageTags_neverNewer() {
        XCTAssertFalse(UpdateChecker.isNewer(remoteTag: "nightly", than: "0.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer(remoteTag: "", than: "0.9.0"))
    }

    func test_availableUpdate_onlyWhenNewer() throws {
        let url = try XCTUnwrap(URL(string: "https://github.com/OkamiOps/OkTally/releases/tag/v1.0.0"))
        XCTAssertEqual(
            UpdateChecker.availableUpdate(remote: (tag: "v1.0.0", url: url), currentVersion: "0.9.0"),
            UpdateInfo(version: "v1.0.0", url: url)
        )
        XCTAssertNil(UpdateChecker.availableUpdate(remote: (tag: "v0.9.0-beta", url: url), currentVersion: "0.9.0"))
        XCTAssertNil(UpdateChecker.availableUpdate(remote: nil, currentVersion: "0.9.0"))
    }
}

// Tests/OkTallyTests/AntigravityUsageProviderTests.swift
import XCTest
@testable import OkTally

final class AntigravityTokenReaderTests: XCTestCase {
    func test_decodeTokens_fromSyntheticBlobInIDEFormat() {
        let blob = AntigravityTokenReader.encodeTestBlob(accessToken: "fake-access-token", refreshToken: "fake-refresh-token")
        let tokens = AntigravityTokenReader.decodeTokens(fromBase64: blob)
        XCTAssertEqual(tokens, AntigravityTokens(accessToken: "fake-access-token", refreshToken: "fake-refresh-token"))
    }

    func test_decodeTokens_garbage_returnsNil() {
        XCTAssertNil(AntigravityTokenReader.decodeTokens(fromBase64: "não-é-base64!!"))
        XCTAssertNil(AntigravityTokenReader.decodeTokens(fromBase64: Data("random".utf8).base64EncodedString()))
    }

    func test_readTokens_missingDatabase_returnsNil() {
        let reader = AntigravityTokenReader(dbPath: "/nonexistent/state.vscdb")
        XCTAssertNil(reader.readTokens())
    }
}

final class AntigravityUsageProviderTests: XCTestCase {
    /// Forma real capturada ao vivo em 2026-08-12.
    private let summaryJSON = """
    {
        "groups": [
            {
                "displayName": "Gemini Models",
                "buckets": [
                    {"bucketId": "gemini-weekly", "displayName": "Weekly Limit", "window": "weekly", "resetTime": "2026-08-19T10:51:46Z", "remainingFraction": 0.4},
                    {"bucketId": "gemini-5h", "displayName": "Five Hour Limit", "window": "5h", "resetTime": "2026-08-12T15:51:46Z", "remainingFraction": 1}
                ]
            },
            {
                "displayName": "Claude and GPT models",
                "buckets": [
                    {"bucketId": "3p-weekly", "displayName": "Weekly Limit", "window": "weekly", "resetTime": "2026-08-19T10:51:46Z", "remainingFraction": 0.93}
                ]
            }
        ]
    }
    """

    func test_windows_mapsGroupsAndBuckets() throws {
        let now = Date()
        let windows = AntigravityUsageProvider.windows(fromSummary: Data(summaryJSON.utf8), now: now)

        XCTAssertEqual(windows.count, 3)
        let byLabel = Dictionary(uniqueKeysWithValues: windows.map { ($0.label, $0.shape) })

        guard case .rollingWindow(let used, let limit, _, let resetAt) = byLabel["Gemini (weekly)"] else {
            return XCTFail("expected Gemini weekly window")
        }
        XCTAssertEqual(used, 60, accuracy: 0.0001)
        XCTAssertEqual(limit, 100)
        XCTAssertEqual(resetAt, ISO8601DateFormatter().date(from: "2026-08-19T10:51:46Z"))

        XCTAssertEqual(byLabel["Gemini (5h)"]?.usedPercent ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(byLabel["Claude/GPT (weekly)"]?.usedPercent ?? -1, 7, accuracy: 0.0001)
    }

    func test_windows_toleratesMissingFractionAndUnknownGroups() {
        let json = """
        {"groups": [
            {"displayName": "Mystery Models", "buckets": [{"window": "5h", "remainingFraction": 0.5}]},
            {"displayName": "Gemini Models", "buckets": [{"window": "5h"}]}
        ]}
        """
        XCTAssertTrue(AntigravityUsageProvider.windows(fromSummary: Data(json.utf8), now: Date()).isEmpty)
        XCTAssertTrue(AntigravityUsageProvider.windows(fromSummary: Data("{}".utf8), now: Date()).isEmpty)
    }

    func test_classification() {
        XCTAssertEqual(ProviderErrorPresentation.classify(AntigravityError.notDetected), .notConfigured)
        XCTAssertEqual(ProviderErrorPresentation.classify(AntigravityError.tokenRejected), .needsReauth)
        XCTAssertEqual(ProviderErrorPresentation.classify(AntigravityError.badResponse(500)), .error)
    }
}

import XCTest
@testable import OkTally

final class ProviderErrorPresentationTests: XCTestCase {
    func test_classify_schedulerNotConfigured_isNotConfigured() {
        XCTAssertEqual(ProviderErrorPresentation.classify(SchedulerError.notConfigured), .notConfigured)
    }

    func test_classify_missingAPIKeyErrors_areNotConfigured() {
        XCTAssertEqual(ProviderErrorPresentation.classify(OpenRouterError.missingAPIKey), .notConfigured)
        XCTAssertEqual(ProviderErrorPresentation.classify(MiniMaxError.missingAPIKey), .notConfigured)
    }

    func test_classify_notDetectedErrors_areNotConfigured() {
        XCTAssertEqual(ProviderErrorPresentation.classify(CursorUsageError.notDetected), .notConfigured)
        XCTAssertEqual(ProviderErrorPresentation.classify(OpenCodeError.notDetected), .notConfigured)
    }

    func test_classify_noRefreshToken_isNeedsReauth() {
        XCTAssertEqual(ProviderErrorPresentation.classify(OAuthError.noRefreshToken), .needsReauth)
        XCTAssertEqual(ProviderErrorPresentation.classify(OAuthError.refreshFailed(401)), .needsReauth)
    }

    func test_classify_deviceCodeDeniedOrExpired_isNeedsReauth() {
        XCTAssertEqual(ProviderErrorPresentation.classify(DeviceCodeError.accessDenied), .needsReauth)
        XCTAssertEqual(ProviderErrorPresentation.classify(DeviceCodeError.expired), .needsReauth)
    }

    func test_classify_networkOrUnexpectedErrors_areError() {
        XCTAssertEqual(ProviderErrorPresentation.classify(OpenRouterError.badResponse(500)), .error)
        XCTAssertEqual(ProviderErrorPresentation.classify(OAuthError.tokenExchangeFailed(400)), .error)
        XCTAssertEqual(ProviderErrorPresentation.classify(OAuthError.portInUse(1455)), .error)
        XCTAssertEqual(ProviderErrorPresentation.classify(CursorUsageError.badResponse(500)), .error)
    }

    func test_grokBotCursorDependencyFailure_isQuietAndHasNoReconnectAction() {
        let kind = ProviderErrorPresentation.classify(GrokBotUsageError.cursorSessionUnavailable)

        XCTAssertEqual(kind, .dependencyUnavailable)
        XCTAssertNil(ProviderPresentationPolicy.recoveryAction(for: kind))
    }

    func test_dependencyFailure_keepsLastGoodSnapshotVisibleInPopoverAndOverview() {
        let snapshot = ProviderSnapshot(
            providerId: "cursor-grokbot",
            fetchedAt: Date(),
            quotas: [QuotaWindow(
                label: "weekly",
                shape: .periodicCounter(used: 22, limit: 100, resetAt: Date())
            )],
            usageDetail: nil,
            planLabel: "Grok Bot Plan"
        )

        XCTAssertTrue(ProviderPresentationPolicy.showsSnapshot(
            snapshot,
            errorKind: .dependencyUnavailable
        ))
        XCTAssertFalse(ProviderPresentationPolicy.showsSnapshot(
            snapshot,
            errorKind: .notConfigured
        ))
    }
}

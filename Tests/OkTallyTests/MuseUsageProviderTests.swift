import XCTest
@testable import OkTally

final class FakeMuseUsageReader: MuseUsageReading {
    var value: MuseUsageReadState?
    var error: Error?

    func readUsage() async throws -> MuseUsageReadState {
        if let error { throw error }
        return try XCTUnwrap(value)
    }
}

final class MuseUsageProviderTests: XCTestCase {
    private func usage(observedAtMs: Int64 = 1_700_000_000_123) -> MuseSubscriptionUsage {
        MuseSubscriptionUsage(
            observedAtMs: observedAtMs,
            tier: "high_usage",
            window: MuseSubscriptionUsageWindow(
                resetsAtMs: 1_700_018_000_000,
                usedPercent: 31,
                windowDurationMins: 300
            ),
            weekly: MuseSubscriptionUsageWeekly(
                resetsAtMs: 1_700_604_800_000,
                usedPercent: 72
            )
        )
    }

    private func account(_ state: String = "accountLogin") -> MuseAccountState {
        MuseAccountState(credentialRequired: true, state: state, label: "Meta account")
    }

    private func makeProvider(
        reader: FakeMuseUsageReader,
        now: @escaping () -> Date = Date.init
    ) -> MuseUsageProvider {
        MuseUsageProvider(
            instanceId: "muse#test",
            authFilePath: "/isolated/muse/auth.json",
            reader: reader,
            now: now
        )
    }

    func test_snapshotUsesObservedArrivalTimestampAndExactWindows() async throws {
        let reader = FakeMuseUsageReader()
        let payload = usage()
        reader.value = MuseUsageReadState(account: account(), usage: payload)
        let snapshot = try await makeProvider(reader: reader).fetchSnapshot()

        XCTAssertEqual(snapshot.providerId, "muse#test")
        XCTAssertEqual(snapshot.fetchedAt, Date(timeIntervalSince1970: 1_700_000_000.123))
        XCTAssertEqual(snapshot.planLabel, "high_usage")
        XCTAssertEqual(snapshot.quotas.map(\.label), ["5h", "semanal"])
        XCTAssertEqual(snapshot.quotas.last?.renewalCadence, .weekly)
        XCTAssertNotNil(snapshot.connectionNote)

        guard case let .rollingWindow(currentUsed, currentLimit, currentStart, currentReset) = snapshot.quotas[0].shape else {
            return XCTFail("expected current rolling window")
        }
        XCTAssertEqual(currentUsed, 31)
        XCTAssertEqual(currentLimit, 100)
        XCTAssertEqual(currentReset, payload.window.resetAt)
        XCTAssertEqual(currentStart, payload.window.resetAt.addingTimeInterval(-300 * 60))

        guard case let .rollingWindow(weeklyUsed, weeklyLimit, weeklyStart, weeklyReset) = snapshot.quotas[1].shape else {
            return XCTFail("expected weekly rolling window")
        }
        XCTAssertEqual(weeklyUsed, 72)
        XCTAssertEqual(weeklyLimit, 100)
        XCTAssertEqual(weeklyReset, payload.weekly.resetAt)
        XCTAssertEqual(weeklyStart, payload.weekly.resetAt.addingTimeInterval(-7 * 24 * 60 * 60))
    }

    func test_noObservedUsageIsTruthfulEmptySnapshotWithoutModelCall() async throws {
        let reader = FakeMuseUsageReader()
        reader.value = MuseUsageReadState(account: account(), usage: nil)
        let readTime = Date(timeIntervalSince1970: 777)
        let snapshot = try await makeProvider(reader: reader, now: { readTime }).fetchSnapshot()

        XCTAssertEqual(snapshot.fetchedAt, readTime)
        XCTAssertTrue(snapshot.quotas.isEmpty)
        XCTAssertNil(snapshot.planLabel)
        XCTAssertNotNil(snapshot.connectionNote)
    }

    func test_apiKeyOrEnvironmentStateIsNotReportedAsSubscriptionLogin() async throws {
        let reader = FakeMuseUsageReader()
        reader.value = MuseUsageReadState(account: account("apiKey"), usage: usage())
        let provider = makeProvider(reader: reader)

        let authenticated = await provider.isAuthenticated()
        XCTAssertFalse(authenticated)
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("API-key state cannot be a Muse subscription connection")
        } catch let error as MuseUsageError {
            XCTAssertEqual(error, .subscriptionLoginRequired)
        }
    }

    func test_negativeProviderValuesAreRejectedRatherThanInvented() async throws {
        let reader = FakeMuseUsageReader()
        reader.value = MuseUsageReadState(
            account: account(),
            usage: MuseSubscriptionUsage(
                observedAtMs: 1,
                tier: "everyday",
                window: MuseSubscriptionUsageWindow(resetsAtMs: 2, usedPercent: -1, windowDurationMins: 300),
                weekly: MuseSubscriptionUsageWeekly(resetsAtMs: 3, usedPercent: 0)
            )
        )

        do {
            _ = try await makeProvider(reader: reader).fetchSnapshot()
            XCTFail("negative values violate the Muse wire contract")
        } catch let error as MuseUsageError {
            XCTAssertEqual(error, .malformedUsage)
        }
    }

    func test_usageReadDecodesOptionalUsageMember() throws {
        let absent = try JSONDecoder().decode(MuseUsageReadResult.self, from: Data("{}".utf8))
        XCTAssertNil(absent.usage)

        let present = try JSONDecoder().decode(MuseUsageReadResult.self, from: Data("""
        {"usage":{"observedAtMs":1700000000123,"tier":"power","window":{"resetsAtMs":1700018000000,"usedPercent":101,"windowDurationMins":300},"weekly":{"resetsAtMs":1700604800000,"usedPercent":4}}}
        """.utf8))
        XCTAssertEqual(present.usage?.window.usedPercent, 101, "over-quota values are valid Muse observations")
    }

    func test_mspWireInitializesExperimentalApiAndUsageReadHasNoSessionId() throws {
        let initialize = try XCTUnwrap(JSONSerialization.jsonObject(with: MuseMSPWire.initialize(id: 1)) as? [String: Any])
        let params = try XCTUnwrap(initialize["params"] as? [String: Any])
        let capabilities = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["experimentalApi"] as? Bool, true)
        XCTAssertEqual((params["clientInfo"] as? [String: Any])?["name"] as? String, "oktally")

        let usageRead = try XCTUnwrap(JSONSerialization.jsonObject(with: MuseMSPWire.request(id: 3, method: "usage/read")) as? [String: Any])
        XCTAssertEqual(usageRead["method"] as? String, "usage/read")
        XCTAssertNil(usageRead["params"])

        let login = try XCTUnwrap(JSONSerialization.jsonObject(with: MuseMSPWire.deviceCodeLoginStart(id: 4)) as? [String: Any])
        XCTAssertEqual(login["method"] as? String, "account/loginStart")
        XCTAssertEqual((login["params"] as? [String: String])?["type"], "deviceCode")
    }

    func test_explicitPlaintextCredentialImportRequiresMuseDocumentAndLocksDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("selected-auth.json")
        let destination = root.appendingPathComponent("per-account/config/muse/auth.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Data(#"{"schema_version":1,"providers":{"meta":{"mechanism":"oauth","access_token":"synthetic"}}}"#.utf8)
        try fixture.write(to: source)

        try MuseCredentialImporter.importPlaintextAuth(from: source, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), fixture)
        let permissions = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(try XCTUnwrap(permissions).intValue & 0o777, 0o600)
        XCTAssertFalse(MuseCredentialImporter.isCompatiblePlaintextAuth(Data("{}".utf8)))
    }
}

import XCTest
@testable import OkTally

final class MiMoSessionRecoveryTests: XCTestCase {
    private let ok = #"{"code":0,"data":{"usage":{"percent":0.5}}}"#
    private let unauthorized = #"{"code":401,"loginUrl":"https://account.xiaomi.com/x"}"#

    func test_healthySession_fetchesOnce_noReload() async throws {
        var fetches = 0, reloads = 0
        let recovery = MiMoSessionRecovery(
            fetch: { fetches += 1; return Data(self.ok.utf8) },
            reload: { reloads += 1 }
        )
        let data = try await recovery.fetchWithRecovery()
        XCTAssertEqual(String(data: data, encoding: .utf8), ok)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(reloads, 0)
    }

    func test_expiredSTS_reloadsConsole_thenSucceeds() async throws {
        var fetches = 0, reloads = 0
        let recovery = MiMoSessionRecovery(
            fetch: { fetches += 1; return Data((fetches == 1 ? self.unauthorized : self.ok).utf8) },
            reload: { reloads += 1 }
        )
        let data = try await recovery.fetchWithRecovery()
        XCTAssertEqual(String(data: data, encoding: .utf8), ok)
        XCTAssertEqual(fetches, 2)
        XCTAssertEqual(reloads, 1, "401 must trigger exactly one console reload (SSO → new STS)")
    }

    func test_deadSSO_still401AfterReload_throwsNotLoggedIn() async {
        var reloads = 0
        let recovery = MiMoSessionRecovery(
            fetch: { Data(self.unauthorized.utf8) },
            reload: { reloads += 1 }
        )
        do {
            _ = try await recovery.fetchWithRecovery()
            XCTFail("expected notLoggedIn")
        } catch let error as MiMoConsoleError {
            XCTAssertEqual(String(describing: error), String(describing: MiMoConsoleError.notLoggedIn))
        } catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(reloads, 1)
    }

    func test_reloadFailure_propagates() async {
        struct Boom: Error {}
        let recovery = MiMoSessionRecovery(
            fetch: { Data(self.unauthorized.utf8) },
            reload: { throw Boom() }
        )
        do { _ = try await recovery.fetchWithRecovery(); XCTFail("expected Boom") }
        catch is Boom {} catch { XCTFail("unexpected \(error)") }
    }
}

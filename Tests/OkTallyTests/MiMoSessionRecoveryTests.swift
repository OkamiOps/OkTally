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
            XCTAssertEqual(error, .notLoggedIn)
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

    // MARK: - Corpos que não são o JSON do console

    func test_htmlLoginPage_alsoTriggersReload_thenSucceeds() async throws {
        // Redirecionado para o SSO: o corpo volta como HTML, não como `{"code":401}`.
        // O reload é exatamente o remédio, então isso não pode passar direto ao decoder.
        var fetches = 0, reloads = 0
        let login = "<html><body><form action=\"https://account.xiaomi.com/pass/serviceLogin\"></form></body></html>"
        let recovery = MiMoSessionRecovery(
            fetch: { fetches += 1; return Data((fetches == 1 ? login : self.ok).utf8) },
            reload: { reloads += 1 }
        )
        let data = try await recovery.fetchWithRecovery()
        XCTAssertEqual(String(data: data, encoding: .utf8), ok)
        XCTAssertEqual(reloads, 1)
    }

    func test_emptyBodyTwice_throwsNoData_notNotLoggedIn() async {
        // SPA ainda bootando / gateway mudo: é tick perdido, não logout. Confundir os dois
        // é o que derrubava a sessão para sempre.
        let recovery = MiMoSessionRecovery(fetch: { Data() }, reload: {})
        do { _ = try await recovery.fetchWithRecovery(); XCTFail("expected noData") }
        catch let error as MiMoConsoleError { XCTAssertEqual(error, .noData) }
        catch { XCTFail("unexpected \(error)") }
    }

    func test_fetchThrowingNotLoggedIn_isRecoverable_viaReload() async throws {
        // A web view pode estar parada em account.xiaomi.com quando o tick começa; o
        // reload roda a cadeia de redirects e o segundo fetch volta bom.
        var fetches = 0, reloads = 0
        let recovery = MiMoSessionRecovery(
            fetch: {
                fetches += 1
                if fetches == 1 { throw MiMoConsoleError.notLoggedIn }
                return Data(self.ok.utf8)
            },
            reload: { reloads += 1 }
        )
        let data = try await recovery.fetchWithRecovery()
        XCTAssertEqual(String(data: data, encoding: .utf8), ok)
        XCTAssertEqual(reloads, 1)
    }

    func test_nonConsoleFetchError_propagatesUntouched() async {
        struct Boom: Error {}
        let recovery = MiMoSessionRecovery(fetch: { throw Boom() }, reload: {})
        do { _ = try await recovery.fetchWithRecovery(); XCTFail("expected Boom") }
        catch is Boom {} catch { XCTFail("unexpected \(error)") }
    }
}

import XCTest
@testable import OkTally

private final class FakeMiMoSessionStore: MiMoSessionStoring {
    var isLoggedIn: Bool = false
}

private final class FakeMiMoUsageFetcher: MiMoUsageFetching {
    var json: String = "{}"
    var errorToThrow: Error?
    private(set) var calls = 0
    func fetchUsageJSON() async throws -> Data {
        calls += 1
        if let errorToThrow { throw errorToThrow }
        return Data(json.utf8)
    }
}

final class MiMoUsageProviderTests: XCTestCase {
    private let unauthorized = #"{"code":401,"loginUrl":"https://account.xiaomi.com/..."}"#

    private func makeProvider(
        session: FakeMiMoSessionStore = FakeMiMoSessionStore(),
        fetcher: FakeMiMoUsageFetcher = FakeMiMoUsageFetcher(),
        allowance: Double? = nil,
        used: Double = 0,
        now: @escaping () -> Date = Date.init
    ) -> MiMoUsageProvider {
        MiMoUsageProvider(
            sessionStore: session, usageFetcher: fetcher,
            allowanceProvider: { allowance }, usedCreditsProvider: { used }, now: now
        )
    }

    func test_isAuthenticated_falseWhenNoSessionAndNoAllowance() async {
        let authenticated = await makeProvider().isAuthenticated()
        XCTAssertFalse(authenticated)
    }

    func test_isAuthenticated_trueWithSession() async {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let authenticated = await makeProvider(session: session).isAuthenticated()
        XCTAssertTrue(authenticated)
    }

    func test_liveSnapshot_mapsPlanAndMonthUsageFromWebSession() async throws {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        // Real tokenPlan/usage shape: percent is a fraction.
        fetcher.json = #"{"code":0,"data":{"monthUsage":{"percent":0.0622},"usage":{"percent":0.06}}}"#
        let snapshot = try await makeProvider(session: session, fetcher: fetcher).fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 2)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "mensal" }?.shape.usedPercent ?? -1, 6.22, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotas.first { $0.label == "plano" }?.shape.usedPercent ?? -1, 6.0, accuracy: 0.001)
    }

    func test_expiredSession_401_keepsFlag_andFallsBackToManual() async throws {
        // O bug: o 401 de UM tick apagava `mimo.loggedIn`, e como `fetchSnapshot` só tenta a
        // web session com o flag ligado, o provider nunca mais voltava sozinho — mesmo com o
        // passToken da Xiaomi vivo nos cookies.
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.json = unauthorized
        let snapshot = try await makeProvider(session: session, fetcher: fetcher, allowance: 500, used: 125).fetchSnapshot()

        XCTAssertTrue(session.isLoggedIn, "só um logout explícito pode apagar o flag")
        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(snapshot.quotas[0].label, "mensal")
        XCTAssertEqual(snapshot.quotas[0].shape.usedPercent, 25)
    }

    func test_401_keepsRetryingTheWebSessionOnLaterTicks() async throws {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.json = unauthorized
        let provider = makeProvider(session: session, fetcher: fetcher, allowance: 500, used: 125)

        _ = try await provider.fetchSnapshot()
        fetcher.json = #"{"code":0,"data":{"usage":{"percent":0.06}}}"#
        let recovered = try await provider.fetchSnapshot()

        XCTAssertEqual(fetcher.calls, 2, "o tick seguinte tem de chamar a web session de novo")
        XCTAssertEqual(recovered.quotas.first { $0.label == "plano" }?.shape.usedPercent ?? -1, 6.0, accuracy: 0.001)
    }

    func test_401WithoutManualEstimate_surfacesTransientError_notPermanentLogout() async {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.json = unauthorized
        let provider = makeProvider(session: session, fetcher: fetcher)

        do { _ = try await provider.fetchSnapshot(); XCTFail("expected sessionRecovering") }
        catch let error as MiMoConsoleError { XCTAssertEqual(error, .sessionRecovering) }
        catch { XCTFail("unexpected \(error)") }
        XCTAssertTrue(session.isLoggedIn)
    }

    func test_401OnEveryTick_eventuallyAsksForReauth_butStillKeepsTrying() async {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.json = unauthorized
        let provider = makeProvider(session: session, fetcher: fetcher, allowance: 500, used: 125)

        for tick in 1..<MiMoUsageProvider.reauthAfterConsecutiveFailures {
            _ = try? await provider.fetchSnapshot()
            XCTAssertEqual(fetcher.calls, tick, "ainda tentando a web session no tick \(tick)")
        }
        do { _ = try await provider.fetchSnapshot(); XCTFail("expected notLoggedIn") }
        catch let error as MiMoConsoleError { XCTAssertEqual(error, .notLoggedIn) }
        catch { XCTFail("unexpected \(error)") }
        XCTAssertTrue(session.isLoggedIn, "nem depois do limiar apagamos o flag")
    }

    func test_successResetsTheFailureStreak() async throws {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        let provider = makeProvider(session: session, fetcher: fetcher, allowance: 500, used: 125)

        for _ in 1..<MiMoUsageProvider.reauthAfterConsecutiveFailures {
            fetcher.json = unauthorized
            _ = try? await provider.fetchSnapshot()
        }
        fetcher.json = #"{"code":0,"data":{"usage":{"percent":0.06}}}"#
        _ = try await provider.fetchSnapshot()

        fetcher.json = unauthorized
        let afterRecovery = try await provider.fetchSnapshot() // volta a ser só um tropeço
        XCTAssertEqual(afterRecovery.quotas[0].shape.usedPercent, 25)
    }

    func test_401WithOddSpacing_isStillRecognised() async throws {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.json = #"{ "msg" : "unauthorized", "code" : 401 }"#
        let snapshot = try await makeProvider(session: session, fetcher: fetcher, allowance: 500, used: 125).fetchSnapshot()

        XCTAssertEqual(snapshot.quotas[0].shape.usedPercent, 25, "401 espaçado tem de cair na estimativa, não estourar no decoder")
    }

    func test_noSession_usesManualEstimate() async throws {
        let snapshot = try await makeProvider(allowance: 400, used: 100).fetchSnapshot()
        XCTAssertEqual(snapshot.quotas[0].label, "mensal")
        XCTAssertEqual(snapshot.quotas[0].shape.usedPercent, 25)
    }

    // MARK: - Erro bruto (não-MiMoConsoleError) escapando da web session

    func test_rawNSURLErrorFromFetcher_isTranslatedToSessionRecovering_notRawText() async {
        // O bug relatado: -999 (navegação superada) escapava intacto até o popover como
        // "The operation couldn't be completed. (NSURLErrorDomain error -999.)". A defesa em
        // profundidade em `fetchSnapshot` garante que QUALQUER erro que não seja do
        // vocabulário do console vira `.sessionRecovering` antes de sair do provider.
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.errorToThrow = NSError(domain: "NSURLErrorDomain", code: -999)
        let provider = makeProvider(session: session, fetcher: fetcher)

        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected sessionRecovering")
        } catch let error as MiMoConsoleError {
            XCTAssertEqual(error, .sessionRecovering)
        } catch {
            XCTFail("erro bruto vazou do provider: \(error)")
        }
        XCTAssertTrue(session.isLoggedIn, "erro transitório não pode apagar o flag de login")
    }

    func test_rawNSURLErrorFromFetcher_fallsBackToManualSnapshot_whenAllowanceConfigured() async throws {
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.errorToThrow = NSError(domain: "NSURLErrorDomain", code: -999)
        let snapshot = try await makeProvider(session: session, fetcher: fetcher, allowance: 500, used: 125).fetchSnapshot()

        XCTAssertEqual(snapshot.quotas.count, 1)
        XCTAssertEqual(snapshot.quotas[0].label, "mensal")
        XCTAssertEqual(snapshot.quotas[0].shape.usedPercent, 25)
    }

    func test_rawNSURLErrorFromFetcher_incrementsFailureStreak_likeAnyOtherFailure() async {
        // Uma sequência de erros brutos tem de contar para o mesmo limiar de reauth que uma
        // sequência de 401 conta — senão um provider preso em -999 nunca pede login de volta
        // nem nunca é tratado como saudável de novo.
        let session = FakeMiMoSessionStore(); session.isLoggedIn = true
        let fetcher = FakeMiMoUsageFetcher()
        fetcher.errorToThrow = NSError(domain: "NSURLErrorDomain", code: -999)
        let provider = makeProvider(session: session, fetcher: fetcher, allowance: 500, used: 125)

        for tick in 1...3 {
            _ = try? await provider.fetchSnapshot()
            XCTAssertEqual(fetcher.calls, tick)
        }
        // Erro bruto nunca é `.notLoggedIn`, então mesmo depois do limiar o provider segue
        // tentando a web session em vez de forçar reauth por um motivo que não é logout.
        fetcher.errorToThrow = nil
        fetcher.json = #"{"code":0,"data":{"usage":{"percent":0.06}}}"#
        let recovered = try? await provider.fetchSnapshot()
        XCTAssertEqual(recovered?.quotas.first { $0.label == "plano" }?.shape.usedPercent ?? -1, 6.0, accuracy: 0.001)
    }

    func test_id_and_refreshInterval() {
        let provider = makeProvider()
        XCTAssertEqual(provider.id, "mimo")
        XCTAssertEqual(provider.refreshInterval, 600)
    }
}

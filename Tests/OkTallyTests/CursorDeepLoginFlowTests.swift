import XCTest
@testable import OkTally

final class CursorDeepLoginFlowTests: XCTestCase {
    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }

    /// Recorder de esperas: prova o backoff sem esperar de verdade.
    final class SleepRecorder {
        var seconds: [Double] = []
    }

    func test_loginURL_containsChallengeUuidAndMode() {
        let start = CursorDeepLoginFlow.makeStart(verifier: "v", uuid: "u-1")
        let items = URLComponents(url: start.browserURL, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(start.browserURL.host, "cursor.com")
        XCTAssertEqual(start.browserURL.path, "/loginDeepControl")
        XCTAssertEqual(items.first { $0.name == "challenge" }?.value, PKCE.challenge(for: "v"))
        XCTAssertEqual(items.first { $0.name == "uuid" }?.value, "u-1")
        XCTAssertEqual(items.first { $0.name == "mode" }?.value, "login")
        XCTAssertEqual(items.first { $0.name == "redirectTarget" }?.value, "cli")
        XCTAssertNil(items.first { $0.name == "verifier" }, "o verifier nunca vai para o navegador")
    }

    func test_begin_usesFreshVerifierAndUuid() {
        let flow = CursorDeepLoginFlow(tokenStore: InMemoryTokenStore())
        let a = flow.begin(), b = flow.begin()
        XCTAssertNotEqual(a.uuid, b.uuid)
        XCTAssertNotEqual(a.verifier, b.verifier)
    }

    func test_poll_404ThenSuccess_savesTokenUnderInstance() async throws {
        let start = CursorDeepLoginFlow.makeStart(verifier: "ver", uuid: "uuid-ok")
        let url = CursorDeepLoginFlow.pollURL(uuid: start.uuid, verifier: start.verifier)
        let jwt = AccountEmailResolverTests.makeJWT(["exp": 2_000_000_000, "type": "session"])
        URLProtocolStub.stubQueues[url] = [
            (Data("Not found".utf8), 404),
            (Data("Not found".utf8), 404),
            (Data(#"{"accessToken":"\#(jwt)","refreshToken":"\#(jwt)","uuid":"uuid-ok"}"#.utf8), 200)
        ]
        let store = InMemoryTokenStore()
        let sleeps = SleepRecorder()
        let flow = CursorDeepLoginFlow(tokenStore: store, session: makeSession(),
                                       sleep: { sleeps.seconds.append(Double($0) / 1e9) })

        let token = try await flow.poll(start, instanceId: "cursor#abc123")

        XCTAssertEqual(token.accessToken, jwt)
        XCTAssertEqual(store.load(providerId: "cursor#abc123")?.accessToken, jwt)
        XCTAssertEqual(store.load(providerId: "cursor#abc123")?.expiresAt, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(sleeps.seconds, [1, 1.5, 2.25])
    }

    func test_poll_nonJWTToken_hasNoExpiry() async throws {
        let start = CursorDeepLoginFlow.makeStart(verifier: "ver2", uuid: "uuid-opaque")
        URLProtocolStub.stubQueues[CursorDeepLoginFlow.pollURL(uuid: start.uuid, verifier: start.verifier)] = [
            (Data(#"{"accessToken":"opaque","refreshToken":"r"}"#.utf8), 200)
        ]
        let store = InMemoryTokenStore()
        let token = try await CursorDeepLoginFlow(tokenStore: store, session: makeSession(), sleep: { _ in })
            .poll(start, instanceId: "cursor#abc123")
        XCTAssertNil(token.expiresAt)
    }

    func test_poll_givesUpAfterMaxAttempts() async {
        let start = CursorDeepLoginFlow.makeStart(verifier: "ver3", uuid: "uuid-never")
        let url = CursorDeepLoginFlow.pollURL(uuid: start.uuid, verifier: start.verifier)
        URLProtocolStub.stubResponses[url] = (Data("Not found".utf8), 404)
        let sleeps = SleepRecorder()
        let flow = CursorDeepLoginFlow(tokenStore: InMemoryTokenStore(), session: makeSession(),
                                       sleep: { sleeps.seconds.append(Double($0) / 1e9) }, maxAttempts: 8)
        do {
            _ = try await flow.poll(start, instanceId: "cursor#abc123")
            XCTFail("expected timeout")
        } catch OAuthError.loginTimeout {
            XCTAssertEqual(sleeps.seconds.count, 8)
            XCTAssertEqual(sleeps.seconds.max(), 10, "backoff tem teto de 10 s")
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func test_defaultMaxAttempts_is150() {
        XCTAssertEqual(CursorDeepLoginFlow.defaultMaxAttempts, 150)
    }
}

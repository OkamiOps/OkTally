import XCTest
@testable import OkTally

final class DeviceCodeFlowTests: XCTestCase {
    private let config = DeviceCodeOAuthConfig(
        providerId: "supergrok",
        deviceAuthorizationURL: URL(string: "https://auth.example.com/oauth2/device/code")!,
        tokenURL: URL(string: "https://auth.example.com/oauth2/token")!,
        clientId: "client123",
        scopes: ["openid", "offline_access"]
    )

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: cfg)
    }

    private func noSleep() -> (UInt64) async throws -> Void { { _ in } }

    func test_requestDeviceCode_parsesVerificationURLAndDeviceCode() async throws {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "supergrok_device_code_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[config.deviceAuthorizationURL] = (data, 200)
        let flow = DeviceCodeFlow(tokenStore: InMemoryTokenStore(), session: makeSession())

        let request = try await flow.requestDeviceCode(config: config)

        XCTAssertEqual(request.deviceCode, "devcode-abc")
        XCTAssertEqual(request.info.userCode, "ABCD-1234")
        XCTAssertEqual(request.info.verificationURL, URL(string: "https://auth.x.ai/activate?user_code=ABCD-1234")!)
        XCTAssertEqual(request.info.expiresInSeconds, 900)
        XCTAssertEqual(request.intervalSeconds, 1)
    }

    func test_requestDeviceCode_nonOKStatus_throwsRequestFailed() async {
        URLProtocolStub.stubResponses[config.deviceAuthorizationURL] = (Data(), 400)
        let flow = DeviceCodeFlow(tokenStore: InMemoryTokenStore(), session: makeSession())

        do {
            _ = try await flow.requestDeviceCode(config: config)
            XCTFail("expected throw")
        } catch DeviceCodeError.requestFailed(let code) {
            XCTAssertEqual(code, 400)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_poll_succeedsImmediately_savesTokenToStore() async throws {
        let tokenData = try Data(contentsOf: Bundle.module.url(forResource: "supergrok_device_token_response", withExtension: "json", subdirectory: "Fixtures")!)
        URLProtocolStub.stubResponses[config.tokenURL] = (tokenData, 200)
        let store = InMemoryTokenStore()
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let flow = DeviceCodeFlow(tokenStore: store, session: makeSession(), now: { fixedNow }, sleep: noSleep())
        let request = DeviceCodeRequest(
            info: DeviceCodeInfo(userCode: "ABCD-1234", verificationURL: URL(string: "https://auth.example.com/activate")!, expiresInSeconds: 900),
            deviceCode: "devcode-abc",
            intervalSeconds: 1
        )

        let token = try await flow.poll(request, config: config)

        XCTAssertEqual(token.accessToken, "new-access")
        XCTAssertEqual(token.refreshToken, "new-refresh")
        XCTAssertEqual(token.expiresAt, fixedNow.addingTimeInterval(3600))
        XCTAssertEqual(store.load(providerId: "supergrok")?.accessToken, "new-access")
    }

    func test_poll_authorizationPendingThenSuccess() async throws {
        final class PendingThenSuccessProtocol: URLProtocol {
            static var callCount = 0
            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                Self.callCount += 1
                let response = HTTPURLResponse(url: request.url!, statusCode: Self.callCount == 1 ? 400 : 200, httpVersion: nil, headerFields: nil)!
                let data: Data
                if Self.callCount == 1 {
                    data = #"{"error":"authorization_pending"}"#.data(using: .utf8)!
                } else {
                    data = #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.data(using: .utf8)!
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }
        PendingThenSuccessProtocol.callCount = 0
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [PendingThenSuccessProtocol.self]
        let session = URLSession(configuration: cfg)

        let store = InMemoryTokenStore()
        let flow = DeviceCodeFlow(tokenStore: store, session: session, sleep: noSleep())
        let request = DeviceCodeRequest(
            info: DeviceCodeInfo(userCode: "ABCD-1234", verificationURL: URL(string: "https://auth.example.com/activate")!, expiresInSeconds: 900),
            deviceCode: "devcode-abc",
            intervalSeconds: 1
        )

        let token = try await flow.poll(request, config: config)

        XCTAssertEqual(token.accessToken, "new-access")
        XCTAssertEqual(PendingThenSuccessProtocol.callCount, 2)
    }

    func test_poll_accessDenied_throws() async {
        let session = makeSession()
        URLProtocolStub.stubResponses[config.tokenURL] = (#"{"error":"access_denied"}"#.data(using: .utf8)!, 400)
        let flow = DeviceCodeFlow(tokenStore: InMemoryTokenStore(), session: session, sleep: noSleep())
        let request = DeviceCodeRequest(
            info: DeviceCodeInfo(userCode: "ABCD-1234", verificationURL: URL(string: "https://auth.example.com/activate")!, expiresInSeconds: 900),
            deviceCode: "devcode-abc",
            intervalSeconds: 1
        )

        do {
            _ = try await flow.poll(request, config: config)
            XCTFail("expected throw")
        } catch DeviceCodeError.accessDenied {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_poll_expiredBeforeApproval_throwsExpired() async {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        // now() never advances, but the deadline is based on expiresInSeconds
        // relative to the first `now()` call; simulate an already-expired
        // window by giving a 0-second budget (clamped to a 60s minimum inside
        // poll, so instead assert via a deadline that's already passed using
        // a now() that jumps forward on each call).
        var callIndex = 0
        let advancingNow: () -> Date = {
            callIndex += 1
            return callIndex == 1 ? fixedNow : fixedNow.addingTimeInterval(1000)
        }
        let flow = DeviceCodeFlow(tokenStore: InMemoryTokenStore(), session: makeSession(), now: advancingNow, sleep: noSleep())
        let request = DeviceCodeRequest(
            info: DeviceCodeInfo(userCode: "ABCD-1234", verificationURL: URL(string: "https://auth.example.com/activate")!, expiresInSeconds: 60),
            deviceCode: "devcode-abc",
            intervalSeconds: 1
        )

        do {
            _ = try await flow.poll(request, config: config)
            XCTFail("expected throw")
        } catch DeviceCodeError.expired {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

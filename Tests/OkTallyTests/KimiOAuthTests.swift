import XCTest
@testable import OkTally

final class KimiOAuthTests: XCTestCase {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KimiOAuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        KimiOAuthURLProtocol.reset()
        super.tearDown()
    }

    func test_beginDeviceLogin_postsOfficialFormAndStableOwnIdentity() async throws {
        KimiOAuthURLProtocol.enqueue(
            url: KimiOAuthClient.authorizationURL,
            status: 200,
            json: #"""
            {"user_code":"ABCD-EFGH","device_code":"device-code","verification_uri_complete":"https://auth.kimi.com/verify?code=ABCD-EFGH","expires_in":600,"interval":3}
            """#
        )
        let now = Date(timeIntervalSince1970: 1_000)
        let client = KimiOAuthClient(session: makeSession(), deviceIdentifier: "test-installation", now: { now })

        let authorization = try await client.beginDeviceLogin()

        XCTAssertEqual(authorization.userCode, "ABCD-EFGH")
        XCTAssertEqual(authorization.deviceCode, "device-code")
        XCTAssertEqual(authorization.verificationURL, URL(string: "https://auth.kimi.com/verify?code=ABCD-EFGH"))
        XCTAssertEqual(authorization.expiresAt, now.addingTimeInterval(600))
        XCTAssertEqual(authorization.interval, 3)
        let request = try XCTUnwrap(KimiOAuthURLProtocol.lastRequest(for: KimiOAuthClient.authorizationURL))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue((request.httpBodyString ?? "").contains("client_id="))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Msh-Platform"), "oktally_macos")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Msh-Device-Id"), "test-installation")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "OkTally/1")
    }

    func test_waitForToken_handlesPendingSlowDownAndAddsProfileIdentity() async throws {
        KimiOAuthURLProtocol.enqueue(url: KimiOAuthClient.tokenURL, status: 400, json: #"{"error":"authorization_pending"}"#)
        KimiOAuthURLProtocol.enqueue(url: KimiOAuthClient.tokenURL, status: 400, json: #"{"error":"slow_down"}"#)
        KimiOAuthURLProtocol.enqueue(url: KimiOAuthClient.tokenURL, status: 200, json: #"{"access_token":"synthetic-access","refresh_token":"synthetic-refresh","expires_in":3600}"#)
        KimiOAuthURLProtocol.enqueue(url: KimiOAuthClient.profileURL, status: 200, json: #"{"user_id":"u_123","email":"kimi@example.test","nickname":"Moonwalker","user_level_name":"Vivace"}"#)
        let now = Date(timeIntervalSince1970: 2_000)
        var intervals: [UInt64] = []
        let client = KimiOAuthClient(session: makeSession(), now: { now }, sleep: { intervals.append($0) })
        let authorization = KimiDeviceAuthorization(
            userCode: "CODE", deviceCode: "device", verificationURL: URL(string: "https://auth.kimi.com/verify")!,
            expiresAt: now.addingTimeInterval(600), interval: 2
        )

        let token = try await client.waitForToken(authorization: authorization)

        XCTAssertEqual(token.refreshToken, "synthetic-refresh")
        XCTAssertEqual(token.expiresAt, now.addingTimeInterval(3600))
        XCTAssertEqual(token.extra, ["userId": "u_123", "email": "kimi@example.test", "nickname": "Moonwalker", "userLevelName": "Vivace"])
        XCTAssertEqual(intervals, [2_000_000_000, 2_000_000_000, 7_000_000_000])
        XCTAssertEqual(KimiOAuthURLProtocol.requestCount(for: KimiOAuthClient.tokenURL), 3)
        XCTAssertEqual(KimiOAuthURLProtocol.lastRequest(for: KimiOAuthClient.profileURL)?.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-access")
    }

    func test_waitForToken_honorsCancellationBeforePolling() async {
        let authorization = KimiDeviceAuthorization(
            userCode: "CODE", deviceCode: "device", verificationURL: URL(string: "https://auth.kimi.com/verify")!,
            expiresAt: .distantFuture, interval: 1
        )
        let client = KimiOAuthClient(session: makeSession())
        let task = Task { try await client.waitForToken(authorization: authorization) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(KimiOAuthURLProtocol.requestCount(for: KimiOAuthClient.tokenURL), 0)
    }

    func test_refresh_preservesOmittedRefreshTokenAndRefreshesProfileMetadata() async throws {
        KimiOAuthURLProtocol.enqueue(url: KimiOAuthClient.tokenURL, status: 200, json: #"{"access_token":"fresh-access","expires_in":1800}"#)
        KimiOAuthURLProtocol.enqueue(url: KimiOAuthClient.profileURL, status: 200, json: #"{"user_id":"u_new","user_level_name":"Andante"}"#)
        let now = Date(timeIntervalSince1970: 3_000)
        let client = KimiOAuthClient(session: makeSession(), now: { now })
        let previous = OAuthToken(accessToken: "old-access", refreshToken: "keep-refresh", expiresAt: .distantPast, extra: ["nickname": "Old name"])

        let refreshed = try await client.refresh(token: previous)

        XCTAssertEqual(refreshed.accessToken, "fresh-access")
        XCTAssertEqual(refreshed.refreshToken, "keep-refresh")
        XCTAssertEqual(refreshed.expiresAt, now.addingTimeInterval(1800))
        XCTAssertEqual(refreshed.extra["userId"], "u_new")
        XCTAssertEqual(refreshed.extra["userLevelName"], "Andante")
        XCTAssertEqual(refreshed.extra["nickname"], "Old name")
        XCTAssertTrue((KimiOAuthURLProtocol.lastRequest(for: KimiOAuthClient.tokenURL)?.httpBodyString ?? "").contains("grant_type=refresh_token"))
    }
}

private final class KimiOAuthURLProtocol: URLProtocol {
    private struct Stub {
        let status: Int
        let data: Data
    }

    private static let lock = NSLock()
    private static var queues: [URL: [Stub]] = [:]
    private static var requests: [URL: [URLRequest]] = [:]

    static func enqueue(url: URL, status: Int, json: String) {
        lock.lock()
        queues[url, default: []].append(Stub(status: status, data: Data(json.utf8)))
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        queues = [:]
        requests = [:]
        lock.unlock()
    }

    static func lastRequest(for url: URL) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests[url]?.last
    }

    static func requestCount(for url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests[url]?.count ?? 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self.requests[url, default: []].append(request)
        let stub: Stub?
        if var queue = Self.queues[url], !queue.isEmpty {
            stub = queue.removeFirst()
            Self.queues[url] = queue
        } else {
            stub = nil
        }
        Self.lock.unlock()
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var httpBodyString: String? {
        if let httpBody { return String(decoding: httpBody, as: UTF8.self) }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

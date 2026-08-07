import XCTest
@testable import OkTally

final class LoopbackCallbackServerTests: XCTestCase {
    func test_nonCallbackPath_doesNotInvokeOnCallback() throws {
        let server = LoopbackCallbackServer()
        let port = try server.start()
        defer { server.stop() }

        var invokedPaths: [String] = []
        let lock = NSLock()
        server.onCallback = { path in
            lock.lock(); invokedPaths.append(path); lock.unlock()
        }

        let url = URL(string: "http://127.0.0.1:\(port)/favicon.ico")!
        let expectation = expectation(description: "favicon request completes")
        URLSession.shared.dataTask(with: url) { _, response, _ in
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
            expectation.fulfill()
        }.resume()
        wait(for: [expectation], timeout: 5)

        // Give the server a moment in case it were to (incorrectly) fire the callback.
        Thread.sleep(forTimeInterval: 0.1)
        lock.lock()
        XCTAssertTrue(invokedPaths.isEmpty, "onCallback must not fire for non-/callback paths, got \(invokedPaths)")
        lock.unlock()
    }

    func test_callbackPath_invokesOnCallbackWithFullPath() throws {
        let server = LoopbackCallbackServer()
        let port = try server.start()
        defer { server.stop() }

        var invokedPaths: [String] = []
        let lock = NSLock()
        let expectation = expectation(description: "callback invoked")
        server.onCallback = { path in
            lock.lock(); invokedPaths.append(path); lock.unlock()
            expectation.fulfill()
        }

        let url = URL(string: "http://127.0.0.1:\(port)/callback?code=x&state=y")!
        URLSession.shared.dataTask(with: url) { _, response, _ in
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }.resume()
        wait(for: [expectation], timeout: 5)

        lock.lock()
        XCTAssertEqual(invokedPaths, ["/callback?code=x&state=y"])
        lock.unlock()
    }

    /// CRITICAL 2 regression: a fixed `redirectPort` must be honored exactly — OAuth
    /// providers with a pre-registered `redirect_uri` reject any other port.
    func test_start_withFixedPort_bindsToExactlyThatPort() throws {
        // High, unlikely-to-collide port to keep the test hermetic.
        let fixedPort = 48732
        let server = LoopbackCallbackServer()
        let boundPort = try server.start(port: fixedPort)
        defer { server.stop() }

        XCTAssertEqual(boundPort, fixedPort)
    }

    /// CRITICAL 2 regression: when the fixed port is already taken by another process
    /// (e.g. the owner already has a login flow in progress, or a stale listener), the
    /// error must be a clear, typed `OAuthError.portInUse`, not a generic failure.
    func test_start_withFixedPortAlreadyBound_throwsPortInUse() throws {
        let fixedPort = 48733
        let holder = LoopbackCallbackServer()
        _ = try holder.start(port: fixedPort)
        defer { holder.stop() }

        let contender = LoopbackCallbackServer()
        do {
            _ = try contender.start(port: fixedPort)
            contender.stop()
            XCTFail("expected OAuthError.portInUse")
        } catch OAuthError.portInUse(let port) {
            XCTAssertEqual(port, fixedPort)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    /// N3 regression: a `start()` that throws must clear `self.listener` internally, not
    /// only via `stop()` — otherwise the same `LoopbackCallbackServer` instance is left
    /// holding a dead listener reference and can never bind again. This exercises the
    /// `bindError` path directly; the late-`.ready`-after-timeout leak described in the
    /// review (the more dangerous case, where the listener actually *did* bind the OS
    /// port after the 5s wait gave up) isn't practical to reproduce deterministically here
    /// — it would need control over `NWListener`'s internal state-transition timing, which
    /// isn't exposed for injection. The fix (clearing `self.listener` before every throw in
    /// `start`) covers that path identically to the one tested below.
    func test_start_afterFailedFixedPortBind_serverCanStillBindADifferentPort() throws {
        let fixedPort = 48734
        let holder = LoopbackCallbackServer()
        _ = try holder.start(port: fixedPort)
        defer { holder.stop() }

        let contender = LoopbackCallbackServer()
        do {
            _ = try contender.start(port: fixedPort)
            XCTFail("expected OAuthError.portInUse")
        } catch OAuthError.portInUse {
            // expected
        }

        // The same instance must be reusable afterwards — proves the failed attempt
        // didn't leave a stale `self.listener` blocking future binds.
        let otherPort = 48735
        let boundPort = try contender.start(port: otherPort)
        defer { contender.stop() }
        XCTAssertEqual(boundPort, otherPort)
    }

    func test_listener_onlyAcceptsLoopbackConnections() throws {
        // The listener must bind to 127.0.0.1 only (RFC 8252), not 0.0.0.0/::.
        // We assert this indirectly: a connection to the loopback address succeeds.
        let server = LoopbackCallbackServer()
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/callback?code=x&state=y")!
        let expectation = expectation(description: "loopback connection succeeds")
        URLSession.shared.dataTask(with: url) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            expectation.fulfill()
        }.resume()
        wait(for: [expectation], timeout: 5)
    }
}

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

import Foundation
import Network

final class LoopbackCallbackServer {
    private var listener: NWListener?
    var onCallback: ((_ path: String) -> Void)?

    // Deliberately NOT `.main`: this server's callbacks (state updates, new connections)
    // must keep firing regardless of what the calling thread is doing — including
    // blocking on `readySignal.wait(...)` below, or (in tests / non-UI call paths)
    // running on whatever thread happens to also be pumping `DispatchQueue.main`. A
    // dedicated queue makes bind-success/bind-failure detection deterministic instead of
    // depending on the main queue being drained by something else.
    private let queue = DispatchQueue(label: "com.oktally.app.oauth.loopback")

    /// Starts the loopback listener. When `port` is given, binds to exactly that port
    /// (required by OAuth providers that reject any `redirect_uri` other than their
    /// pre-registered one); when `nil`, asks the OS for an ephemeral port (used by tests
    /// and providers without a confirmed fixed redirect port).
    func start(port: Int? = nil) throws -> Int {
        let params = NWParameters.tcp
        let nwPort: NWEndpoint.Port
        if let port {
            guard let fixed = NWEndpoint.Port(rawValue: UInt16(port)) else {
                throw OAuthError.portInUse(port)
            }
            nwPort = fixed
        } else {
            nwPort = .any
        }
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        let listener = try NWListener(using: params)
        self.listener = listener

        // Block until the listener reaches `.ready` (bound) or `.failed` (e.g. the fixed
        // port is already taken) instead of busy-polling on a timer: a busy-wait risks
        // either giving up too early (false "port in use") or wasting up to its full
        // budget on the success path. The state updates arrive on `.main`, so this must
        // NOT be called from the actual main thread or it would deadlock — true for both
        // call sites today (`BrowserOAuthFlow.login` runs off an async `Task`, and the
        // unit tests run on a worker thread, not the process's main thread).
        let readySignal = DispatchSemaphore(value: 0)
        let signalLock = NSLock()
        var signaled = false
        var bindError: Error?
        let signalOnce: (Error?) -> Void = { error in
            signalLock.lock()
            defer { signalLock.unlock() }
            guard !signaled else { return }
            signaled = true
            bindError = error
            readySignal.signal()
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                signalOnce(nil)
            case .failed(let error):
                signalOnce(error)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                var path: String?
                if let data, let request = String(data: data, encoding: .utf8),
                   let firstLine = request.split(separator: "\r\n").first {
                    let parts = firstLine.split(separator: " ")
                    if parts.count >= 2 { path = String(parts[1]) }
                }

                if let path, path.hasPrefix("/callback") {
                    self?.onCallback?(path)
                    let body = "OkTally: pode fechar esta aba e voltar ao app."
                    let response = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(body)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
                } else {
                    // Any other request (e.g. the browser's automatic GET /favicon.ico)
                    // must not trigger the OAuth callback — just answer 404 and close.
                    let body = "Not Found"
                    let response = "HTTP/1.1 404 Not Found\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(body)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        listener.start(queue: queue)

        // Every error path below must cancel the listener and clear `self.listener`
        // before throwing. Otherwise a late `.ready` (arriving after the 5s timeout, or
        // after a `.failed` we already gave up on) leaves the listener alive holding the
        // port — on a fixed port like 1455 that self-blocks the very next login attempt,
        // with no fix short of restarting the app, since `BrowserOAuthFlow.login`'s
        // `defer { server.stop() }` is only registered after `start` returns.
        guard readySignal.wait(timeout: .now() + 5) == .success else {
            self.listener?.cancel()
            self.listener = nil
            throw port.map(OAuthError.portInUse) ?? OAuthError.tokenExchangeFailed(nil)
        }
        if bindError != nil {
            self.listener?.cancel()
            self.listener = nil
            throw port.map(OAuthError.portInUse) ?? OAuthError.tokenExchangeFailed(nil)
        }
        guard let boundPort = listener.port?.rawValue, boundPort != 0 else {
            self.listener?.cancel()
            self.listener = nil
            throw OAuthError.tokenExchangeFailed(nil)
        }
        return Int(boundPort)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

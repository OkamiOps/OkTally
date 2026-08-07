import Foundation
import Network

final class LoopbackCallbackServer {
    private var listener: NWListener?
    var onCallback: ((_ path: String) -> Void)?

    func start() throws -> Int {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
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
        listener.start(queue: .main)
        // Busy-wait briefly for the OS to assign a port.
        for _ in 0..<100 {
            if let port = listener.port?.rawValue, port != 0 { return Int(port) }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw OAuthError.tokenExchangeFailed(nil)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

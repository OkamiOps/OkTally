import Foundation
import Network

final class LoopbackCallbackServer {
    private var listener: NWListener?
    var onCallback: ((_ path: String) -> Void)?

    func start() throws -> Int {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                if let data, let request = String(data: data, encoding: .utf8),
                   let firstLine = request.split(separator: "\r\n").first {
                    let parts = firstLine.split(separator: " ")
                    if parts.count >= 2 { self?.onCallback?(String(parts[1])) }
                }
                let body = "OkTally: pode fechar esta aba e voltar ao app."
                let response = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(body)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
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

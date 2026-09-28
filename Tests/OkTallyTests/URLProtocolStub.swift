import Foundation

final class URLProtocolStub: URLProtocol {
    static var stubResponses: [URL: (Data, Int)] = [:]
    /// Respostas em sequência para a mesma URL (polling). Consumidas em ordem; esgotada a
    /// fila, cai em `stubResponses`.
    static var stubQueues: [URL: [(Data, Int)]] = [:]

    private static let countLock = NSLock()
    private static var _requestCounts: [URL: Int] = [:]
    private static var _lastBodies: [URL: Data] = [:]
    private static var _lastAuthorization: [URL: String] = [:]

    /// Cabeçalho `Authorization` da última requisição para a URL.
    static func lastAuthorization(for url: URL) -> String? {
        countLock.lock()
        defer { countLock.unlock() }
        return _lastAuthorization[url]
    }

    /// Corpo da última requisição para a URL (o `URLProtocol` recebe o corpo como stream).
    static func lastBody(for url: URL) -> String? {
        countLock.lock()
        defer { countLock.unlock() }
        return _lastBodies[url].map { String(decoding: $0, as: UTF8.self) }
    }

    private static func recordBody(_ data: Data, for url: URL) {
        countLock.lock()
        defer { countLock.unlock() }
        _lastBodies[url] = data
    }

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    static func requestCount(for url: URL) -> Int {
        countLock.lock()
        defer { countLock.unlock() }
        return _requestCounts[url] ?? 0
    }

    static func resetRequestCounts() {
        countLock.lock()
        defer { countLock.unlock() }
        _requestCounts = [:]
    }

    private static func recordRequest(to url: URL) {
        countLock.lock()
        defer { countLock.unlock() }
        _requestCounts[url, default: 0] += 1
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var queued: (Data, Int)?
        if let url = request.url {
            Self.countLock.lock()
            if var queue = Self.stubQueues[url], !queue.isEmpty {
                queued = queue.removeFirst()
                Self.stubQueues[url] = queue
            }
            Self.countLock.unlock()
        }
        guard let url = request.url, let (data, status) = queued ?? Self.stubResponses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.recordRequest(to: url)
        if let body = Self.body(of: request) { Self.recordBody(body, for: url) }
        if let auth = request.value(forHTTPHeaderField: "Authorization") {
            Self.countLock.lock()
            Self._lastAuthorization[url] = auth
            Self.countLock.unlock()
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

import Foundation

final class URLProtocolStub: URLProtocol {
    static var stubResponses: [URL: (Data, Int)] = [:]

    private static let countLock = NSLock()
    private static var _requestCounts: [URL: Int] = [:]

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
        guard let url = request.url, let (data, status) = Self.stubResponses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.recordRequest(to: url)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

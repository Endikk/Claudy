import Foundation

/// Answers for `api.anthropic.com` only; any other host goes to the real network untouched.
final class StubbedAnthropic: URLProtocol {

    nonisolated(unsafe) static var usage: (Int, Data) = (500, Data())
    nonisolated(unsafe) static var profile: (Int, Data) = (404, Data())
    nonisolated(unsafe) static var usageRequests = 0

    static func reset() {
        usage = (500, Data())
        profile = (404, Data())
        usageRequests = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.anthropic.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let answer: (Int, Data)
        if url.path.hasSuffix("/usage") {
            Self.usageRequests += 1
            answer = Self.usage
        } else {
            answer = Self.profile
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.0, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

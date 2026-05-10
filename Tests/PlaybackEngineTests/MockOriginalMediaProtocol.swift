import Foundation

final class MockOriginalMediaProtocol: URLProtocol {
    static var storage = Data()
    static var contentType = "video/mp4"
    static var rangeRequestCount = 0
    static var requestedURLs: [URL] = []
    static var requestedHeaders: [[String: String]] = []

    static func reset() {
        storage = Data()
        contentType = "video/mp4"
        rangeRequestCount = 0
        requestedURLs = []
        requestedHeaders = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "media.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let url = request.url {
            Self.requestedURLs.append(url)
        }
        Self.requestedHeaders.append(request.allHTTPHeaderFields ?? [:])
        let data = Self.storage
        let method = request.httpMethod?.uppercased() ?? "GET"
        if method == "HEAD" {
            send(statusCode: 200, data: nil, headers: [
                "Content-Length": "\(data.count)",
                "Accept-Ranges": "bytes",
                "Content-Type": Self.contentType
            ])
            return
        }

        Self.rangeRequestCount += 1
        guard
            let range = request.value(forHTTPHeaderField: "Range"),
            let parsed = parseRange(range, upperBound: data.count)
        else {
            send(statusCode: 200, data: data, headers: [
                "Content-Length": "\(data.count)",
                "Accept-Ranges": "bytes",
                "Content-Type": Self.contentType
            ])
            return
        }

        let slice = data[parsed]
        send(statusCode: 206, data: Data(slice), headers: [
            "Content-Range": "bytes \(parsed.lowerBound)-\(parsed.upperBound - 1)/\(data.count)",
            "Content-Length": "\(slice.count)",
            "Accept-Ranges": "bytes",
            "Content-Type": Self.contentType
        ])
    }

    override func stopLoading() {}

    private func send(statusCode: Int, data: Data?, headers: [String: String]) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    private func parseRange(_ value: String, upperBound: Int) -> Range<Int>? {
        guard value.hasPrefix("bytes=") else { return nil }
        let parts = value
            .dropFirst("bytes=".count)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 2,
              let start = Int(parts[0]),
              start >= 0 else { return nil }
        let requestedEnd: Int
        if parts[1].isEmpty {
            requestedEnd = max(0, upperBound - 1)
        } else if let end = Int(parts[1]), end >= start {
            requestedEnd = end
        } else {
            return nil
        }
        let boundedEnd = min(requestedEnd, max(0, upperBound - 1))
        return start..<(boundedEnd + 1)
    }
}

import Foundation
import NativeMediaCore

struct LocalMediaGatewayHTTPRequest {
    let method: String
    let path: String
    let range: LocalMediaGatewayRequestedRange?

    init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else { return nil }
        let header = text[..<headerEnd.lowerBound]
        let lines = header.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        self.method = parts[0].uppercased()
        self.path = parts[1]
        self.range = lines.compactMap(Self.range(fromHeaderLine:)).first
    }

    private static func range(fromHeaderLine line: String) -> LocalMediaGatewayRequestedRange? {
        let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard pair.count == 2, pair[0].lowercased() == "range" else { return nil }
        let value = pair[1].trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("bytes=") else { return nil }
        let bounds = value
            .dropFirst(6)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty, let suffixLength = Int(bounds[1]), suffixLength > 0 {
            return .suffix(length: suffixLength)
        }
        guard let start = Int64(bounds[0]), start >= 0 else { return nil }
        if bounds[1].isEmpty {
            return .openEnded(offset: start)
        }
        guard let end = Int64(bounds[1]), end >= start else { return nil }
        return .bounded(ByteRange(offset: start, length: Int(end - start + 1)))
    }
}

enum LocalMediaGatewayRequestedRange: Equatable {
    case bounded(ByteRange)
    case openEnded(offset: Int64)
    case suffix(length: Int)
}

enum LocalMediaGatewayHTTPResponse {
    static func head(totalLength: Int64?, contentType: String?, keepAlive: Bool = false) -> Data {
        response(status: "200 OK", headers: commonHeaders(totalLength: totalLength, contentType: contentType, keepAlive: keepAlive), body: nil)
    }

    static func partial(data: Data, range: ByteRange, totalLength: Int64?, contentType: String?, keepAlive: Bool = false) -> Data {
        var response = partialHeaders(range: range, totalLength: totalLength, contentType: contentType, keepAlive: keepAlive)
        response.append(data)
        return response
    }

    static func partialHeaders(range: ByteRange, totalLength: Int64?, contentType: String?, keepAlive: Bool = false) -> Data {
        var headers = commonHeaders(totalLength: Int64(range.length), contentType: contentType, keepAlive: keepAlive)
        let total = totalLength.map(String.init) ?? "*"
        let end = range.offset + Int64(range.length) - 1
        headers["Content-Range"] = "bytes \(range.offset)-\(end)/\(total)"
        return response(status: "206 Partial Content", headers: headers, body: nil)
    }

    static func rangeNotSatisfiable(totalLength: Int64?) -> Data {
        var headers = ["Content-Length": "0"]
        if let totalLength {
            headers["Content-Range"] = "bytes */\(totalLength)"
        }
        return response(status: "416 Range Not Satisfiable", headers: headers, body: nil)
    }

    static func notFound() -> Data {
        response(status: "404 Not Found", headers: ["Content-Length": "0"], body: nil)
    }

    static func badRequest() -> Data {
        response(status: "400 Bad Request", headers: ["Content-Length": "0"], body: nil)
    }

    static func serverError() -> Data {
        response(status: "502 Bad Gateway", headers: ["Content-Length": "0"], body: nil)
    }

    private static func commonHeaders(totalLength: Int64?, contentType: String?, keepAlive: Bool = false) -> [String: String] {
        [
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-store",
            // Keep-alive lets AVPlayer reuse ONE socket for its many ranged reads. With "close" it
            // opened a new connection per range (hundreds), each a separate active serve, which made
            // the downloader's playhead targeting thrash and starve playback despite a deep cache.
            "Connection": keepAlive ? "keep-alive" : "close",
            "Content-Length": "\(max(0, totalLength ?? 0))",
            "Content-Type": contentType ?? "application/octet-stream"
        ]
    }

    private static func response(status: String, headers: [String: String], body: Data?) -> Data {
        var data = Data("HTTP/1.1 \(status)\r\n".utf8)
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            data.append(Data("\(name): \(value)\r\n".utf8))
        }
        data.append(Data("\r\n".utf8))
        if let body {
            data.append(body)
        }
        return data
    }
}

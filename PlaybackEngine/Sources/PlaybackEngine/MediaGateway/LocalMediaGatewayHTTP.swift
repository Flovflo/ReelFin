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
        let rangeLines = lines.dropFirst().filter(Self.isRangeHeaderLine)
        guard rangeLines.count <= 1 else { return nil }
        if let rangeLine = rangeLines.first {
            guard let range = Self.range(fromHeaderLine: rangeLine) else { return nil }
            self.range = range
        } else {
            self.range = nil
        }
    }

    private static func isRangeHeaderLine(_ line: String) -> Bool {
        let name = line.split(separator: ":", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces)
        return name?.lowercased() == "range"
    }

    private static func range(fromHeaderLine line: String) -> LocalMediaGatewayRequestedRange? {
        let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "range" else { return nil }
        let value = pair[1].trimmingCharacters(in: .whitespaces)
        guard value.prefix(6).lowercased() == "bytes=", !value.contains(",") else { return nil }
        let bounds = value
            .dropFirst(6)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty, let suffixLength = parseNonnegativeInt64(bounds[1]), suffixLength > 0,
           let length = Int(exactly: suffixLength) {
            return .suffix(length: length)
        }
        guard let start = parseNonnegativeInt64(bounds[0]) else { return nil }
        if bounds[1].isEmpty {
            return .openEnded(offset: start)
        }
        guard let end = parseNonnegativeInt64(bounds[1]), end >= start else { return nil }
        return .bounded(LocalMediaGatewayBoundedRange(offset: start, endInclusive: end))
    }

    private static func parseNonnegativeInt64(_ text: String) -> Int64? {
        guard !text.isEmpty, text.allSatisfy(\.isNumber) else { return nil }
        return Int64(text)
    }
}

struct LocalMediaGatewayBoundedRange: Equatable {
    let offset: Int64
    let endInclusive: Int64

    init(offset: Int64, endInclusive: Int64) {
        self.offset = offset
        self.endInclusive = endInclusive
    }

    init(_ range: ByteRange) {
        let (endExclusive, overflow) = range.offset.addingReportingOverflow(Int64(range.length))
        if range.length > 0, !overflow {
            self.offset = range.offset
            self.endInclusive = endExclusive - 1
        } else {
            self.offset = range.offset
            self.endInclusive = Int64.min
        }
    }

    var length: Int {
        let (distance, subtractionOverflow) = endInclusive.subtractingReportingOverflow(offset)
        guard !subtractionOverflow else { return 0 }
        let (inclusiveLength, additionOverflow) = distance.addingReportingOverflow(1)
        guard !additionOverflow, let length = Int(exactly: inclusiveLength) else { return 0 }
        return length
    }
}

struct LocalMediaGatewayResolvedRange: Equatable {
    let start: Int64
    let endExclusive: Int64

    init?(start: Int64, endExclusive: Int64) {
        guard start >= 0, endExclusive > start else { return nil }
        self.start = start
        self.endExclusive = endExclusive
    }

    init?(_ range: ByteRange) {
        guard range.offset >= 0, range.length > 0 else { return nil }
        let (endExclusive, overflow) = range.offset.addingReportingOverflow(Int64(range.length))
        guard !overflow else { return nil }
        self.init(start: range.offset, endExclusive: endExclusive)
    }

    var length: Int64 { endExclusive - start }
    var endInclusive: Int64 { endExclusive - 1 }
}

enum LocalMediaGatewayRequestedRange: Equatable {
    case bounded(LocalMediaGatewayBoundedRange)
    case openEnded(offset: Int64)
    case suffix(length: Int)

    static func bounded(_ range: ByteRange) -> Self {
        .bounded(LocalMediaGatewayBoundedRange(range))
    }

    func resolve(totalLength: Int64) -> LocalMediaGatewayResolvedRange? {
        guard totalLength > 0 else { return nil }
        switch self {
        case .bounded(let requested):
            guard requested.offset < totalLength,
                  requested.endInclusive < totalLength else { return nil }
            let (endExclusive, overflow) = requested.endInclusive.addingReportingOverflow(1)
            guard !overflow else { return nil }
            return LocalMediaGatewayResolvedRange(start: requested.offset, endExclusive: endExclusive)
        case .openEnded(let offset):
            guard offset < totalLength else { return nil }
            return LocalMediaGatewayResolvedRange(start: offset, endExclusive: totalLength)
        case .suffix(let length):
            guard length > 0 else { return nil }
            let requestedLength = Int64(length)
            let start: Int64
            if requestedLength >= totalLength {
                start = 0
            } else {
                let (candidate, overflow) = totalLength.subtractingReportingOverflow(requestedLength)
                guard !overflow else { return nil }
                start = candidate
            }
            return LocalMediaGatewayResolvedRange(start: start, endExclusive: totalLength)
        }
    }
}

extension MediaAccessError {
    static func invalidRange(_ range: LocalMediaGatewayBoundedRange) -> Self {
        .invalidRange(ByteRange(offset: range.offset, length: range.length))
    }
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
        guard let resolved = LocalMediaGatewayResolvedRange(range) else {
            return rangeNotSatisfiable(totalLength: totalLength)
        }
        return partialHeaders(range: resolved, totalLength: totalLength, contentType: contentType, keepAlive: keepAlive)
    }

    static func partialHeaders(
        range: LocalMediaGatewayResolvedRange,
        totalLength: Int64?,
        contentType: String?,
        keepAlive: Bool = false
    ) -> Data {
        var headers = commonHeaders(totalLength: range.length, contentType: contentType, keepAlive: keepAlive)
        let total = totalLength.map(String.init) ?? "*"
        headers["Content-Range"] = "bytes \(range.start)-\(range.endInclusive)/\(total)"
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

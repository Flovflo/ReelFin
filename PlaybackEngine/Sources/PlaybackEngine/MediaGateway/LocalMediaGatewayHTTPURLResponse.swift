import Foundation

extension HTTPURLResponse {
    var mediaGatewayContentLength: Int64? {
        guard let raw = value(forHTTPHeaderField: "Content-Length") else { return nil }
        return Int64(raw)
    }

    var mediaGatewayContentRangeTotal: Int64? {
        guard let raw = value(forHTTPHeaderField: "Content-Range"),
              let slash = raw.lastIndex(of: "/") else { return nil }
        return Int64(raw[raw.index(after: slash)...])
    }
}

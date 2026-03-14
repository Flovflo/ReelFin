import Foundation
import Shared

struct HybridVLCResolvedEndpoint: Equatable {
    let url: URL
    let headers: [String: String]
}

struct HybridVLCURLResolver {
    func resolve(
        source: MediaSource,
        configuration: ServerConfiguration,
        session: UserSession?
    ) -> HybridVLCResolvedEndpoint? {
        let token = session?.token

        if let directURL = source.directPlayURL ?? source.directStreamURL {
            return HybridVLCResolvedEndpoint(
                url: injectingAPIKeyIfNeeded(directURL, token: token),
                headers: resolvedHeaders(for: source, token: token)
            )
        }

        if let rawURL = constructDirectStreamURL(
            itemID: source.itemID,
            sourceID: source.id,
            serverURL: configuration.serverURL,
            token: token
        ) {
            return HybridVLCResolvedEndpoint(
                url: rawURL,
                headers: resolvedHeaders(for: source, token: token)
            )
        }

        if let transcodeURL = source.transcodeURL {
            return HybridVLCResolvedEndpoint(
                url: injectingAPIKeyIfNeeded(transcodeURL, token: token),
                headers: resolvedHeaders(for: source, token: token)
            )
        }

        return nil
    }

    private func constructDirectStreamURL(
        itemID: String,
        sourceID: String,
        serverURL: URL,
        token: String?
    ) -> URL? {
        guard !itemID.isEmpty, !sourceID.isEmpty else { return nil }

        var components = URLComponents(
            url: serverURL.appendingPathComponent("Videos/\(itemID)/stream"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "MediaSourceId", value: sourceID)
        ]
        if let token, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private func injectingAPIKeyIfNeeded(_ url: URL, token: String?) -> URL {
        guard let token, !token.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name.lowercased() == "api_key" }) {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
            components.queryItems = queryItems
        }
        return components.url ?? url
    }

    private func resolvedHeaders(for source: MediaSource, token: String?) -> [String: String] {
        var headers = source.requiredHTTPHeaders
        if let token, !token.isEmpty {
            headers["X-Emby-Token"] = token
        }
        return headers
    }
}

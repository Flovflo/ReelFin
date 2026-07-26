import Foundation
import Shared
import SwiftUI

extension CachedRemoteImageContentMode {
    var identity: String {
        switch self {
        case .fill:
            return "fill"
        case .fit:
            return "fit"
        }
    }
}

struct RemoteImageScalingModifier: ViewModifier {
    let contentMode: CachedRemoteImageContentMode

    func body(content: Content) -> some View {
        switch contentMode {
        case .fill:
            content.scaledToFill()
        case .fit:
            content.scaledToFit()
        }
    }
}

struct CachedRemoteImageRequestToken: Hashable, Sendable {
    fileprivate let generation: UInt
    let consumerID: ImageRequestConsumerID
}

struct CachedRemoteImageCancellation: Hashable, Sendable {
    let url: URL
    let consumerID: ImageRequestConsumerID
}

struct CachedRemoteImageRequestState: Sendable {
    private var generation: UInt = 0
    private var activeToken: CachedRemoteImageRequestToken?
    private(set) var requestURL: URL?
    var contentKey: String?

    mutating func begin() -> (
        token: CachedRemoteImageRequestToken,
        cancellation: CachedRemoteImageCancellation?
    ) {
        let cancellation = activeCancellation
        generation &+= 1
        let token = CachedRemoteImageRequestToken(
            generation: generation,
            consumerID: ImageRequestConsumerID()
        )
        activeToken = token
        requestURL = nil
        return (token, cancellation)
    }

    func owns(_ token: CachedRemoteImageRequestToken) -> Bool {
        activeToken == token
    }

    mutating func attach(
        _ url: URL,
        to token: CachedRemoteImageRequestToken
    ) -> CachedRemoteImageCancellation? {
        guard owns(token) else { return nil }
        let cancellation = requestURL.flatMap { attachedURL in
            attachedURL == url
                ? nil
                : CachedRemoteImageCancellation(url: attachedURL, consumerID: token.consumerID)
        }
        requestURL = url
        return cancellation
    }

    mutating func finish(_ token: CachedRemoteImageRequestToken) {
        guard owns(token) else { return }
        activeToken = nil
        requestURL = nil
    }

    mutating func invalidate() -> CachedRemoteImageCancellation? {
        let cancellation = activeCancellation
        generation &+= 1
        activeToken = nil
        requestURL = nil
        return cancellation
    }

    private var activeCancellation: CachedRemoteImageCancellation? {
        guard let activeToken, let requestURL else { return nil }
        return CachedRemoteImageCancellation(url: requestURL, consumerID: activeToken.consumerID)
    }
}

extension CachedRemoteImage {
    static func fallbackType(for sourceType: JellyfinImageType) -> JellyfinImageType? {
        switch sourceType {
        case .primary:
            return .backdrop
        case .backdrop:
            return .primary
        case .logo:
            return nil
        }
    }

    static func shouldIgnoreImageError(_ error: Error) -> Bool {
        error.localizedDescription.lowercased().contains("404")
    }
}

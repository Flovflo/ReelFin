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

struct CachedRemoteImageRequestState: Sendable {
    var consumerID = ImageRequestConsumerID()
    var requestURL: URL?
    var contentKey: String?

    mutating func nextConsumerID() -> ImageRequestConsumerID {
        let consumerID = ImageRequestConsumerID()
        self.consumerID = consumerID
        return consumerID
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

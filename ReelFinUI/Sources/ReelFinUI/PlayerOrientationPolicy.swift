#if os(iOS)
import UIKit

enum PlayerOrientationContext: CaseIterable {
    case browsing
    case player
}

enum PlayerOrientationPolicy {
    static func supportedOrientations(
        idiom: UIUserInterfaceIdiom,
        context: PlayerOrientationContext
    ) -> UIInterfaceOrientationMask {
        if idiom == .pad {
            return .all
        }

        switch context {
        case .browsing:
            return .portrait
        case .player:
            return .landscape
        }
    }

    static func requestedGeometryOrientation(
        idiom: UIUserInterfaceIdiom,
        context: PlayerOrientationContext
    ) -> UIInterfaceOrientationMask? {
        if idiom == .pad {
            return nil
        }

        switch context {
        case .browsing:
            return .portrait
        case .player:
            return .landscapeRight
        }
    }
}
#endif

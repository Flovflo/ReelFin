#if targetEnvironment(macCatalyst)
import SwiftUI

enum MacRootDestination: String, CaseIterable, Identifiable {
    case home
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .library:
            return "Library"
        case .settings:
            return "Settings"
        }
    }

    var detail: String {
        switch self {
        case .home:
            return "Continue watching"
        case .library:
            return "Movies and shows"
        case .settings:
            return "Server and playback"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "play.tv.fill"
        case .library:
            return "rectangle.stack.fill"
        case .settings:
            return "gearshape.fill"
        }
    }

    static let browseDestinations: [MacRootDestination] = [.home, .library]
    static let accountDestinations: [MacRootDestination] = [.settings]
}
#endif

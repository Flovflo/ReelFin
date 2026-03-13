import SwiftUI

enum TVRootDestination: String, CaseIterable, Hashable {
    case watchNow
    case search
    case library

    var title: String {
        switch self {
        case .watchNow: "Watch Now"
        case .search: "Search"
        case .library: "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .watchNow: "play.rectangle.fill"
        case .search: "magnifyingglass"
        case .library: "rectangle.stack.fill"
        }
    }

    var prefersContentBehindNavigationBar: Bool {
        self == .watchNow
    }
}

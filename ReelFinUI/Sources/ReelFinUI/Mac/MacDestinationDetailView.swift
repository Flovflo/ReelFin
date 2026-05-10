#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacDestinationDetailView: View {
    let destination: MacRootDestination
    let refreshID: Int
    let dependencies: ReelFinDependencies
    let onSignOut: () -> Void
    let onToggleSidebar: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        NavigationStack {
            content
                .id(contentID)
                .navigationTitle(destination.title)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: onToggleSidebar) {
                            Label("Toggle Sidebar", systemImage: "sidebar.leading")
                        }
                        .labelStyle(.iconOnly)
                        .help("Toggle Sidebar")
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: onRefresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh")
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .home:
            HomeView(dependencies: dependencies)
        case .library:
            LibraryView(dependencies: dependencies)
        case .settings:
            ServerSettingsView(dependencies: dependencies, onLogout: onSignOut)
        }
    }

    private var contentID: String {
        "\(destination.rawValue)-\(refreshID)"
    }
}
#endif

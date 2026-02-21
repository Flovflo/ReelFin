import Shared
import SwiftUI

public struct ReelFinRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: RootViewModel
    private let dependencies: ReelFinDependencies

    @State private var selectedTab = 0
    @State private var selectedSidebar: SidebarDestination? = .home

    public init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: RootViewModel(dependencies: dependencies))
    }

    public var body: some View {
        Group {
            if !viewModel.didBootstrap {
                ZStack {
                    ReelFinTheme.pageGradient.ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            } else if viewModel.isAuthenticated {
                if horizontalSizeClass == .regular {
                    splitLayout
                } else {
                    mainTabs
                }
            } else {
                LoginView(dependencies: dependencies) { session in
                    viewModel.completeLogin(session)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.bootstrap()
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(dependencies: dependencies)
            }
            .tag(0)
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                LibraryView(dependencies: dependencies)
            }
            .tag(1)
            .tabItem {
                Label("Library", systemImage: "square.grid.2x2.fill")
            }

            NavigationStack {
                ServerSettingsView(dependencies: dependencies) {
                    viewModel.signOut()
                }
            }
            .tag(2)
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(ReelFinTheme.accent)
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(selection: $selectedSidebar) {
                Label("Home", systemImage: "house.fill")
                    .tag(SidebarDestination.home)
                Label("Library", systemImage: "square.grid.2x2.fill")
                    .tag(SidebarDestination.library)
                Label("Settings", systemImage: "gearshape.fill")
                    .tag(SidebarDestination.settings)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(ReelFinTheme.pageGradient)
            .navigationTitle("ReelFin")
        } detail: {
            Group {
                switch selectedSidebar ?? .home {
                case .home:
                    NavigationStack {
                        HomeView(dependencies: dependencies)
                    }
                case .library:
                    NavigationStack {
                        LibraryView(dependencies: dependencies)
                    }
                case .settings:
                    NavigationStack {
                        ServerSettingsView(dependencies: dependencies) {
                            viewModel.signOut()
                        }
                    }
                }
            }
        }
        .tint(ReelFinTheme.accent)
    }
}

private enum SidebarDestination: Hashable {
    case home
    case library
    case settings
}

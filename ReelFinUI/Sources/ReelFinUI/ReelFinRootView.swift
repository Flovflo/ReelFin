import Shared
import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct ReelFinRootView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var viewModel: RootViewModel
    private let dependencies: ReelFinDependencies

    @State private var selectedTab = 0
    #if os(iOS)
    @State private var selectedSidebar: SidebarDestination? = .home
    #endif

    public init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: RootViewModel(dependencies: dependencies))
    }

    public var body: some View {
        Group {
            if !viewModel.didBootstrap {
                ZStack {
                    ReelFinTheme.pageGradient.ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            } else if viewModel.isAuthenticated {
                #if os(tvOS)
                tvLayout
                #else
                if shouldUseSplitLayout {
                    splitLayout
                } else {
                    mainTabs
                }
                #endif
            } else {
#if os(tvOS)
                TVAuthFlowView(dependencies: dependencies) { session in
                    viewModel.completeLogin(session)
                }
#else
                LoginView(dependencies: dependencies) { session in
                    viewModel.completeLogin(session)
                }
#endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.bootstrap()
        }
    }

    #if os(tvOS)
    private var tvLayout: some View {
        TVRootShellView(dependencies: dependencies)
    }
    #endif

    #if os(iOS)
    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "play.tv.fill", value: 0) {
                NavigationStack {
                    HomeView(dependencies: dependencies)
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: 1, role: .search) {
                NavigationStack {
                    LibraryView(dependencies: dependencies)
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                NavigationStack {
                    ServerSettingsView(dependencies: dependencies) {
                        viewModel.signOut()
                    }
                }
            }
        }
        // iOS 18 behavior to minimize the tab bar on scroll
        .tabBarMinimizeBehavior(.automatic)
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(selection: $selectedSidebar) {
                Label("Home", systemImage: "play.tv.fill")
                    .tag(SidebarDestination.home)
                Label("Search", systemImage: "magnifyingglass")
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

    private var shouldUseSplitLayout: Bool {
        if AppMetadata.current.isScreenshotModeEnabled {
            return false
        }
        return UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    #endif
}

#if os(iOS)
private enum SidebarDestination: Hashable {
    case home
    case library
    case settings
}
#endif

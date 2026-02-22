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
        ZStack(alignment: .bottom) {
            // Main Content Area
            Group {
                switch selectedTab {
                case 0:
                    NavigationStack {
                        HomeView(dependencies: dependencies)
                    }
                case 1:
                    NavigationStack {
                        LibraryView(dependencies: dependencies)
                    }
                case 2:
                    NavigationStack {
                        ServerSettingsView(dependencies: dependencies) {
                            viewModel.signOut()
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Extra padding to ensure the floating tab bar doesn't completely cover the bottom content
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80)
            }

            // Floating Pill Tab Bar
            floatingTabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom) // Keep it clean when search/keyboard is up
    }

    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            tabBarItem(icon: "play.tv.fill", title: "Home", tab: 0)
            tabBarItem(icon: "magnifyingglass", title: "Search", tab: 1)
            tabBarItem(icon: "gearshape.fill", title: "Settings", tab: 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.bottom, 16)
        .padding(.horizontal, 32)
    }

    private func tabBarItem(icon: String, title: String, tab: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
            }
            .foregroundStyle(selectedTab == tab ? Color.white : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
}

private enum SidebarDestination: Hashable {
    case home
    case library
    case settings
}

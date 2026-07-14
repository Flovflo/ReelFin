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
    @State private var dependencies: ReelFinDependencies
    @State private var isReviewDemoMode = false
    @AppStorage(ReelFinDisplayDensity.storageKey) private var displayDensityRawValue = ReelFinDisplayDensity.standard.rawValue
    private let initialDependencies: ReelFinDependencies

    @State private var selectedTab = 0
    #if os(iOS)
    @State private var selectedSidebar: SidebarDestination? = .home
    #endif

    public init(dependencies: ReelFinDependencies) {
        initialDependencies = dependencies
        _dependencies = State(initialValue: dependencies)
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
                #elseif targetEnvironment(macCatalyst)
                if shouldUseMacRootLayout {
                    macLayout
                } else if shouldUseSplitLayout {
                    splitLayout
                } else {
                    mainTabs
                }
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
                    completeLogin(session)
                }
#else
                LoginView(dependencies: dependencies) { session in
                    completeLogin(session)
                }
#endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.reelFinDisplayDensity, displayDensity)
        .task {
            await viewModel.bootstrap()
        }
    }

    private var displayDensity: ReelFinDisplayDensity {
        ReelFinDisplayDensity(rawStoredValue: displayDensityRawValue)
    }

    #if os(tvOS)
    private var tvLayout: some View {
        TVRootShellView(dependencies: dependencies)
    }
    #endif

    #if targetEnvironment(macCatalyst)
    private var macLayout: some View {
        MacRootShellView(dependencies: dependencies) {
            signOut()
        }
    }
    #endif

    #if os(iOS)
    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(PhoneTabDestination.presentationOrder, id: \.self) { destination in
                switch destination {
                case .home:
                    Tab("Home", systemImage: "play.tv.fill", value: destination.rawValue) {
                        NavigationStack {
                            HomeView(dependencies: dependencies)
                        }
                    }
                case .settings:
                    Tab("Settings", systemImage: "gearshape.fill", value: destination.rawValue) {
                        NavigationStack {
                            ServerSettingsView(dependencies: dependencies) {
                                signOut()
                            }
                        }
                    }
                case .search:
                    Tab("Search", systemImage: "magnifyingglass", value: destination.rawValue, role: .search) {
                        NavigationStack {
                            LibraryView(dependencies: dependencies)
                        }
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
                            signOut()
                        }
                    }
                }
            }
        }
        .tint(ReelFinTheme.accent)
    }

    private var shouldUseSplitLayout: Bool {
        RootLayoutPlatformPolicy.shouldUseSplitLayout(
            isScreenshotMode: AppMetadata.current.isScreenshotModeEnabled,
            isRegularHorizontalSizeClass: horizontalSizeClass == .regular,
            isPadIdiom: UIDevice.current.userInterfaceIdiom == .pad,
            isMacCatalyst: RootLayoutPlatformPolicy.isMacCatalystRuntime
        )
    }

    private var shouldUseMacRootLayout: Bool {
        RootLayoutPlatformPolicy.shouldUseMacRootLayout(
            isScreenshotMode: AppMetadata.current.isScreenshotModeEnabled,
            isMacCatalyst: RootLayoutPlatformPolicy.isMacCatalystRuntime
        )
    }
    #endif

    private func completeLogin(_ session: UserSession) {
        guard ReviewDemoMode.isReviewSession(session) else {
            viewModel.completeLogin(session)
            return
        }

        let reviewDependencies = ReelFinPreviewFactory.appStoreDependencies(authenticated: true)
        let reviewViewModel = RootViewModel(dependencies: reviewDependencies)
        reviewViewModel.completeLogin(session)
        dependencies = reviewDependencies
        viewModel = reviewViewModel
        isReviewDemoMode = true
    }

    private func signOut() {
        guard isReviewDemoMode else {
            viewModel.signOut()
            return
        }

        let resetViewModel = RootViewModel(dependencies: initialDependencies)
        dependencies = initialDependencies
        viewModel = resetViewModel
        isReviewDemoMode = false
        resetViewModel.signOut()
    }
}

#if os(iOS)
enum PhoneTabDestination: Int, CaseIterable {
    case home = 0
    case search = 1
    case settings = 2

    /// Keep the primary destinations contiguous so SwiftUI presents the
    /// search role as the separate native Liquid Glass control.
    static let presentationOrder: [Self] = [.home, .settings, .search]
}

private enum SidebarDestination: Hashable {
    case home
    case library
    case settings
}
#endif

#if os(tvOS)
import SwiftUI

struct TVRootShellView: View {
    @State private var selectedDestination: TVRootDestination = .watchNow
    @State private var isTopNavigationVisible = true
    @State private var topNavigationAppearance = TVTopNavigationAppearance.neutral
    @State private var homeRefreshRequest = 0
    @State private var homeHeroFocusRequest = 0
    @FocusState private var focusedDestination: TVRootDestination?

    let dependencies: ReelFinDependencies

    var body: some View {
        ZStack(alignment: .top) {
            TVRootContentView(
                selectedDestination: selectedDestination,
                homeRefreshRequest: homeRefreshRequest,
                homeHeroFocusRequest: homeHeroFocusRequest,
                dependencies: dependencies
            )

            TVTopNavigationOverlayView(
                selectedDestination: $selectedDestination,
                focusedDestination: $focusedDestination,
                isVisible: isTopNavigationVisible,
                appearance: topNavigationAppearance,
                onMoveCommand: handleTopNavigationMove
            )
        }
        .background(ReelFinTheme.pageGradient.ignoresSafeArea())
        .environment(\.tvTopNavigationFocusAction, focusTopNavigation)
        .onPreferenceChange(TVTopNavigationVisibilityPreferenceKey.self) { isVisible in
            isTopNavigationVisible = isVisible
        }
        .onPreferenceChange(TVTopNavigationAppearancePreferenceKey.self) { appearance in
            if selectedDestination == .watchNow {
                topNavigationAppearance = appearance
            }
        }
        .onChange(of: selectedDestination) { _, newDestination in
            if newDestination != .watchNow {
                topNavigationAppearance = .neutral
            }
        }
        .preferredColorScheme(.dark)
    }

    private func focusTopNavigation(_ destination: TVRootDestination) {
        guard isTopNavigationVisible else { return }
        focusedDestination = destination
    }

    private func handleTopNavigationMove(_ destination: TVRootDestination, direction: MoveCommandDirection) {
        guard selectedDestination == .watchNow,
              focusedDestination == .watchNow,
              destination == .watchNow else { return }

        switch direction {
        case .up:
            homeRefreshRequest += 1
        case .down:
            homeHeroFocusRequest += 1
        default:
            break
        }
    }
}

private struct TVRootContentView: View {
    let selectedDestination: TVRootDestination
    let homeRefreshRequest: Int
    let homeHeroFocusRequest: Int
    let dependencies: ReelFinDependencies

    var body: some View {
        NavigationStack {
            content
                .id(selectedDestination)
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
        }
        .animation(TVMotion.contentFadeAnimation, value: selectedDestination)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedDestination {
        case .watchNow:
            HomeView(
                dependencies: dependencies,
                tvRefreshRequest: homeRefreshRequest,
                tvHeroFocusRequest: homeHeroFocusRequest
            )
        case .search:
            TVSearchView(dependencies: dependencies)
                .safeAreaPadding(.top, navigationBarReservedHeight)
        case .library:
            LibraryView(dependencies: dependencies)
                .safeAreaPadding(.top, navigationBarReservedHeight)
        }
    }

    private var navigationBarReservedHeight: CGFloat {
        ReelFinTheme.tvTopNavigationBarHeight + 34
    }
}
#endif

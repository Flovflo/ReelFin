#if os(tvOS)
import SwiftUI

struct TVRootShellView: View {
    @State private var selectedDestination: TVRootDestination = .watchNow
    @State private var isTopNavigationVisible = true
    @State private var topNavigationAppearance = TVTopNavigationAppearance.neutral
    @FocusState private var focusedDestination: TVRootDestination?

    let dependencies: ReelFinDependencies

    var body: some View {
        ZStack(alignment: .top) {
            TVRootContentView(
                selectedDestination: selectedDestination,
                dependencies: dependencies
            )

            TVTopNavigationOverlayView(
                selectedDestination: $selectedDestination,
                focusedDestination: $focusedDestination,
                isVisible: isTopNavigationVisible,
                appearance: topNavigationAppearance
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
}

private struct TVRootContentView: View {
    let selectedDestination: TVRootDestination
    let dependencies: ReelFinDependencies

    var body: some View {
        NavigationStack {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedDestination {
        case .watchNow:
            HomeView(dependencies: dependencies)
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

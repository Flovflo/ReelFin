import SwiftUI

struct TVRootShellView: View {
    @State private var selectedDestination: TVRootDestination = .watchNow
    @State private var isTopNavigationVisible = true
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
                isVisible: isTopNavigationVisible
            )
        }
        .background(ReelFinTheme.pageGradient.ignoresSafeArea())
        .onPreferenceChange(TVTopNavigationVisibilityPreferenceKey.self) { isVisible in
            isTopNavigationVisible = isVisible
        }
        .preferredColorScheme(.dark)
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

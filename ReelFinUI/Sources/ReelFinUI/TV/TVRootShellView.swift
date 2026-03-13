import SwiftUI

struct TVRootShellView: View {
    @State private var selectedDestination: TVRootDestination = .watchNow
    @FocusState private var focusedDestination: TVRootDestination?

    let dependencies: ReelFinDependencies

    var body: some View {
        ZStack(alignment: .top) {
            TVRootContentView(
                selectedDestination: selectedDestination,
                dependencies: dependencies
            )

            TVTopBackdropOverlay()

            TVTopNavigationBar(
                selectedDestination: $selectedDestination,
                focusedDestination: $focusedDestination
            )
            .padding(.top, 22)
        }
        .background(ReelFinTheme.pageGradient.ignoresSafeArea())
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

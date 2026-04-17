#if os(tvOS)
import SwiftUI

struct TVRootShellView: View {
    @State private var selectedDestination: TVRootDestination = .watchNow
    @State private var isTopNavigationVisible = true
    @State private var topNavigationAppearance = TVTopNavigationAppearance.neutral
    @State private var contentFocusSequence = 0
    @State private var hasRequestedInitialContentFocus = false
    @State private var isNavigationFocusable = false
    @FocusState private var focusedDestination: TVRootDestination?

    let dependencies: ReelFinDependencies

    var body: some View {
        ZStack(alignment: .top) {
            TVRootContentView(
                selectedDestination: selectedDestination,
                dependencies: dependencies,
                contentFocusRequest: TVContentFocusRequest(
                    destination: selectedDestination,
                    sequence: contentFocusSequence
                )
            )

            TVTopNavigationOverlayView(
                selectedDestination: $selectedDestination,
                focusedDestination: $focusedDestination,
                isVisible: isTopNavigationVisible,
                appearance: topNavigationAppearance,
                isFocusable: isNavigationFocusable,
                onMoveDownFromNavigation: requestContentFocus
            )
        }
        .background(ReelFinTheme.pageGradient.ignoresSafeArea())
        .environment(\.tvTopNavigationFocusAction, focusTopNavigation)
        .environment(\.tvContentFocusReadyAction, handleContentFocusReady)
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
        .task {
            guard !hasRequestedInitialContentFocus else { return }
            hasRequestedInitialContentFocus = true

            // Let the initial layout settle, then hand focus to the active screen
            // so Home can start on the hero instead of the top navigation rail.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                requestContentFocus(for: selectedDestination)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func focusTopNavigation(_ destination: TVRootDestination) {
        guard isTopNavigationVisible else { return }
        isNavigationFocusable = true
        if selectedDestination != destination {
            selectedDestination = destination
        }
        focusedDestination = destination
    }

    private func requestContentFocus(for destination: TVRootDestination) {
        guard isTopNavigationVisible else { return }

        if selectedDestination != destination {
            selectedDestination = destination
        }

        isNavigationFocusable = false
        focusedDestination = nil
        contentFocusSequence += 1
    }

    private func handleContentFocusReady(_ destination: TVRootDestination, _ sequence: Int) {
        guard destination == selectedDestination else { return }
        guard sequence == contentFocusSequence else { return }

        isNavigationFocusable = true
    }
}

private struct TVRootContentView: View {
    let selectedDestination: TVRootDestination
    let dependencies: ReelFinDependencies
    let contentFocusRequest: TVContentFocusRequest

    var body: some View {
        NavigationStack {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedDestination {
        case .watchNow:
            HomeView(
                dependencies: dependencies,
                contentFocusRequest: contentFocusRequest
            )
        case .search:
            TVSearchView(
                dependencies: dependencies,
                contentFocusRequest: contentFocusRequest
            )
                .safeAreaPadding(.top, navigationBarReservedHeight)
        case .library:
            LibraryView(
                dependencies: dependencies,
                contentFocusRequest: contentFocusRequest
            )
                .safeAreaPadding(.top, navigationBarReservedHeight)
        }
    }

    private var navigationBarReservedHeight: CGFloat {
        ReelFinTheme.tvTopNavigationBarHeight + 34
    }
}
#endif

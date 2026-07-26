#if os(tvOS)
import Shared
import SwiftUI

enum TVLibraryControlFocus: Hashable {
    case movies
    case shows
    case sort
}

struct TVLibraryControlBar: View {
    let selectedFilter: MediaType
    let sortMode: LibraryViewModel.SortMode
    let focusedControl: FocusState<TVLibraryControlFocus?>.Binding
    let allowsTopNavigationRedirect: Bool
    let onFilterChange: (MediaType) -> Void
    let onSortToggle: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Library")
                    .reelFinTitleStyle()

                Text("Browse movies and series with the same focus rhythm as Home.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 24)

            controls
        }
        .padding(.horizontal, 56)
        .padding(.top, 22)
        .focusSection()
    }

    @ViewBuilder
    private var controls: some View {
        if #available(tvOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                controlRow
            }
        } else {
            controlRow
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            TVLibraryPillButton(
                title: "Movies",
                isSelected: selectedFilter == .movie,
                topNavigationDestination: .library,
                allowsTopNavigationRedirect: allowsTopNavigationRedirect,
                focusedControl: focusedControl,
                focusID: .movies
            ) {
                onFilterChange(.movie)
            }
            TVLibraryPillButton(
                title: "Shows",
                isSelected: selectedFilter == .series,
                topNavigationDestination: .library,
                allowsTopNavigationRedirect: allowsTopNavigationRedirect,
                focusedControl: focusedControl,
                focusID: .shows
            ) {
                onFilterChange(.series)
            }

            TVLibraryPillButton(
                title: sortMode.displayTitle,
                systemImage: "arrow.up.arrow.down",
                isSelected: false,
                topNavigationDestination: .library,
                allowsTopNavigationRedirect: allowsTopNavigationRedirect,
                focusedControl: focusedControl,
                focusID: .sort,
                action: onSortToggle
            )
        }
    }
}

private extension LibraryViewModel.SortMode {
    var displayTitle: String {
        switch self {
        case .recent:
            return "Recent"
        case .title:
            return "A-Z"
        }
    }
}
#endif

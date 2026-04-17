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
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Library")
                    .reelFinTitleStyle()

                Text("Browse movies and series with the same focus rhythm as Home.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 18)

            controls
        }
        .padding(.horizontal, 44)
        .padding(.top, 16)
        .focusSection()
    }

    private var controls: some View {
        HStack(spacing: 10) {
            controlRow
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(railBackground)
                .overlay(railStroke)
                .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)

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

    private var controlRow: some View {
        HStack(spacing: 10) {
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
        }
    }

    private var railBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        Glass.regular.tint(Color.white.opacity(0.12)),
                        in: .capsule
                    )
            } else {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.10))
            }
        }
    }

    private var railStroke: some View {
        Capsule(style: .continuous)
            .stroke(Color.white.opacity(0.10), lineWidth: 1)
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

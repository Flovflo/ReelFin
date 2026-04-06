#if os(tvOS)
import Shared
import SwiftUI

struct TVLibraryControlBar: View {
    let selectedFilter: MediaType?
    let sortMode: LibraryViewModel.SortMode
    let onFilterChange: (MediaType?) -> Void
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
    }

    private var controls: some View {
        HStack(spacing: 14) {
            controlRow
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(railBackground)
                .overlay(railStroke)
                .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 10)

            TVLibraryPillButton(
                title: sortMode.displayTitle,
                systemImage: "arrow.up.arrow.down",
                isSelected: false,
                action: onSortToggle
            )
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            TVLibraryPillButton(title: "Movies", isSelected: selectedFilter == .movie) {
                onFilterChange(.movie)
            }
            TVLibraryPillButton(title: "Shows", isSelected: selectedFilter == .series) {
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

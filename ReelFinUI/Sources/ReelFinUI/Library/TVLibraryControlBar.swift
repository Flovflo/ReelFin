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
            .background(quietSortBackground)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            TVLibraryPillButton(title: "All", isSelected: selectedFilter == nil) {
                onFilterChange(nil)
            }
            TVLibraryPillButton(title: "Movies", isSelected: selectedFilter == .movie) {
                onFilterChange(.movie)
            }
            TVLibraryPillButton(title: "Shows", isSelected: selectedFilter == .series) {
                onFilterChange(.series)
            }
        }
    }

    private var railBackground: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.10))
    }

    private var railStroke: some View {
        Capsule(style: .continuous)
            .stroke(Color.white.opacity(0.10), lineWidth: 1)
    }

    private var quietSortBackground: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.10))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
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

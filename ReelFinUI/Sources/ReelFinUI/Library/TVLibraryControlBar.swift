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

                Text("Browse movies and series with a clean focus-first layout.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 24)

            controls
        }
        .padding(.horizontal, 56)
        .padding(.top, 22)
    }

    @ViewBuilder
    private var controls: some View {
        if #available(tvOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { controlRow }
        } else {
            controlRow
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
            TVLibraryPillButton(
                title: sortMode.displayTitle,
                systemImage: "arrow.up.arrow.down",
                isSelected: false,
                action: onSortToggle
            )
        }
    }
}

private struct TVLibraryPillButton: View {
    @FocusState private var isFocused: Bool

    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .font(.system(size: 21, weight: .semibold, design: .rounded))
        .foregroundStyle(isFocused || isSelected ? Color.black.opacity(0.92) : Color.white.opacity(0.92))
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background { background }
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isFocused ? 1.04 : 1)
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: action)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityRepresentation { Button(title, action: action) }
    }

    private var background: some View {
        Color.clear.reelFinGlassCapsule(
            interactive: true,
            tint: isFocused ? Color.white.opacity(0.28) : (isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.08)),
            stroke: Color.white.opacity(isFocused ? 0.26 : (isSelected ? 0.18 : 0.10)),
            shadowOpacity: isFocused ? 0.18 : 0.10,
            shadowRadius: isFocused ? 18 : 10,
            shadowYOffset: isFocused ? 8 : 4
        )
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

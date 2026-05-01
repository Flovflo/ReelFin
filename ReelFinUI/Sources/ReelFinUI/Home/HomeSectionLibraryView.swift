import Shared
import SwiftUI

struct HomeSectionLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.reelFinDisplayDensity) private var displayDensity
    @Namespace private var posterNamespace

    private let dependencies: ReelFinDependencies
    @ObservedObject private var homeViewModel: HomeViewModel
    private let fallbackRow: HomeRow
    private let rowID: String

    @State private var selectedDetailItem: MediaItem?
    @State private var selectedPreferredEpisode: MediaItem?
    @State private var selectedDetailTransitionSourceID: String?

    init(dependencies: ReelFinDependencies, homeViewModel: HomeViewModel, row: HomeRow) {
        self.dependencies = dependencies
        self.homeViewModel = homeViewModel
        fallbackRow = row
        rowID = row.id
    }

    var body: some View {
        ZStack {
            ReelFinTheme.pageGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, topPadding)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: gridSpacing) {
                        ForEach(entries) { entry in
                            gridCell(for: entry)
                        }

                        if homeViewModel.isLoadingMore(rowID: rowID) {
                            ProgressView()
                                .tint(.white)
                                .frame(width: gridCardWidth, height: gridCardWidth * 1.55)
                                .accessibilityLabel("Loading more")
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, bottomPadding)
                }
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { selectedDetailItem != nil },
                set: { newValue in
                    if !newValue {
                        selectedDetailItem = nil
                        selectedPreferredEpisode = nil
                        selectedDetailTransitionSourceID = nil
                    }
                }
            )
        ) {
            if let selectedDetailItem {
                DetailView(
                    dependencies: dependencies,
                    item: selectedDetailItem,
                    preferredEpisode: selectedPreferredEpisode,
                    contextItems: row.items,
                    contextTitle: row.title,
                    namespace: posterNamespace,
                    transitionSourceID: selectedDetailTransitionSourceID,
                    onDisplayedSourceItemChange: handleDisplayedSourceItemChange
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .glassPanelStyle(cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text(row.title)
                .reelFinTitleStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
    }

    private func gridCell(for entry: HomeSectionLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: displayDensity.scaledSpacing(10)) {
            Button {
                select(entry)
            } label: {
                PosterCardArtworkView(
                    item: entry.item,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    layoutStyle: .grid,
                    namespace: posterNamespace,
                    transitionSourceID: transitionSourceID(for: entry)
                )
            }
            .accessibilityIdentifier("home_section_media_card_button_\(row.kind.rawValue)_\(entry.item.id)")
            .buttonStyle(.plain)
            .onAppear {
                Task {
                    await homeViewModel.loadMoreIfNeeded(rowID: rowID, visibleItemID: entry.item.id)
                }
            }

            PosterCardMetadataView(
                item: entry.item,
                layoutStyle: .grid,
                titleLineLimit: 2
            )
        }
    }

    private func select(_ entry: HomeSectionLibraryEntry) {
        selectedDetailTransitionSourceID = transitionSourceID(for: entry)
        selectedPreferredEpisode = entry.item.mediaType == .episode ? entry.item : nil
        selectedDetailItem = detailItem(for: entry.item)

        let detailItemID = entry.item.mediaType == .episode ? (entry.item.parentID ?? entry.item.id) : entry.item.id
        Task {
            await DetailPresentationTelemetry.shared.beginNavigation(for: detailItemID)
        }
    }

    private func handleDisplayedSourceItemChange(_ item: MediaItem) {
        guard let entry = entries.first(where: { $0.item.id == item.id }) else {
            selectedDetailTransitionSourceID = nil
            return
        }

        selectedDetailTransitionSourceID = transitionSourceID(for: entry)
    }

    private func detailItem(for item: MediaItem) -> MediaItem {
        guard item.mediaType == .episode, let seriesID = item.parentID else {
            return item
        }

        return MediaItem(
            id: seriesID,
            name: item.seriesName ?? item.name,
            overview: item.overview,
            mediaType: .series,
            year: item.year,
            runtimeTicks: item.runtimeTicks,
            genres: item.genres,
            communityRating: item.communityRating,
            posterTag: item.seriesPosterTag ?? item.posterTag,
            backdropTag: item.backdropTag,
            libraryID: item.libraryID
        )
    }

    private func transitionSourceID(for entry: HomeSectionLibraryEntry) -> String {
        HomeCardTransitionSource.id(
            rowID: transitionRowID,
            itemID: entry.item.id,
            occurrenceID: "grid-index-\(entry.index)"
        )
    }

    private var transitionRowID: String {
        "home-section.\(row.id)"
    }

    private var row: HomeRow {
        homeViewModel.visibleRows.first(where: { $0.id == rowID }) ?? fallbackRow
    }

    private var entries: [HomeSectionLibraryEntry] {
        row.items.enumerated().map { index, item in
            HomeSectionLibraryEntry(index: index, item: item)
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: gridCardWidth, maximum: gridCardWidth),
                spacing: gridSpacing,
                alignment: .top
            )
        ]
    }

    private var gridCardWidth: CGFloat {
        PosterCardMetrics.posterWidth(
            for: .grid,
            compact: horizontalSizeClass == .compact,
            displayDensity: displayDensity
        )
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvRailSpacing
        #else
        return displayDensity.scaledSpacing(horizontalSizeClass == .compact ? 18 : 24)
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvSectionHorizontalPadding
        #else
        return displayDensity.scaledSpacing(horizontalSizeClass == .compact ? 24 : 40)
        #endif
    }

    private var topPadding: CGFloat {
        #if os(tvOS)
        return ReelFinTheme.tvTopNavigationBarHeight + 28
        #else
        return 8
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(tvOS)
        return 72
        #else
        return 116
        #endif
    }
}

private struct HomeSectionLibraryEntry: Identifiable {
    let index: Int
    let item: MediaItem

    var id: String {
        "\(index)-\(item.id)"
    }
}

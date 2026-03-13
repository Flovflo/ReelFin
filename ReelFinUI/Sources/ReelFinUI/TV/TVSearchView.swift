// TVSearchView.swift – Apple TV search with controlled tvOS layout

#if os(tvOS)
import Shared
import SwiftUI

@MainActor
final class TVSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [MediaItem] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var selectedItem: MediaItem?

    private let dependencies: ReelFinDependencies
    private var searchTask: Task<Void, Never>?

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
    }

    func search() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }

            do {
                let items = try await dependencies.repository.searchItems(query: trimmed, limit: 40)
                guard !Task.isCancelled else { return }
                results = items
            } catch {
                guard !Task.isCancelled else { return }
                results = []
            }

            hasSearched = true
            isSearching = false
        }
    }

    func select(item: MediaItem) {
        if item.mediaType == .episode, let seriesID = item.parentID {
            selectedItem = MediaItem(
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
        } else {
            selectedItem = item
        }
    }

    func dismissDetail() {
        selectedItem = nil
    }
}

struct TVSearchView: View {
    @Environment(\.tvTopNavigationFocusAction) private var requestTopNavigationFocus
    @FocusState private var isSearchFieldFocused: Bool
    @StateObject private var viewModel: TVSearchViewModel
    private let dependencies: ReelFinDependencies

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 30)]

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: TVSearchViewModel(dependencies: dependencies))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            searchHeader
            searchContent
        }
        .padding(.horizontal, 72)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .onChange(of: viewModel.query) { _, _ in
            viewModel.search()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.selectedItem != nil },
                set: { if !$0 { viewModel.dismissDetail() } }
            )
        ) {
            if let item = viewModel.selectedItem {
                DetailView(dependencies: dependencies, item: item)
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Search")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 18) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))

                TextField("Movies, shows, cast, directors", text: $viewModel.query)
                    .focused($isSearchFieldFocused)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .submitLabel(.search)
                    .onMoveCommand { direction in
                        guard direction == .up else { return }
                        requestTopNavigationFocus?(.search)
                    }
            }
            .padding(.horizontal, 28)
            .frame(width: 920, height: 84, alignment: .leading)
            .background(ReelFinTheme.tvSurfaceMutedFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(isSearchFieldFocused ? ReelFinTheme.tvStrongStroke : ReelFinTheme.tvStroke, lineWidth: isSearchFieldFocused ? 1.4 : 1)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if viewModel.isSearching {
            TVSearchStateView(
                icon: "progress.indicator",
                title: "Searching",
                subtitle: "Looking through your library."
            )
        } else if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            TVSearchStateView(
                icon: "magnifyingglass",
                title: "Search your library",
                subtitle: "Type a title, actor, series, or movie."
            )
        } else if viewModel.hasSearched && viewModel.results.isEmpty {
            TVSearchStateView(
                icon: "film.stack",
                title: "No results",
                subtitle: "Try a shorter term or another spelling."
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 34) {
                    ForEach(viewModel.results) { item in
                        TVSearchCardButton(
                            item: item,
                            dependencies: dependencies,
                            onSelect: { viewModel.select(item: $0) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .focusSection()
        }
    }
}

private struct TVSearchStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 62, weight: .thin))
                .foregroundStyle(.white.opacity(0.46))
            Text(title)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
            Text(subtitle)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TVSearchCardButton: View {
    @FocusState private var isFocused: Bool

    let item: MediaItem
    let dependencies: ReelFinDependencies
    let onSelect: (MediaItem) -> Void

    var body: some View {
        PosterCardView(
            item: item,
            apiClient: dependencies.apiClient,
            imagePipeline: dependencies.imagePipeline,
            layoutStyle: .grid,
            titleLineLimit: 2
        )
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture { onSelect(item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
    }
}
#endif

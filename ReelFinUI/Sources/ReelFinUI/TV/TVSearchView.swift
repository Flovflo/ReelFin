// TVSearchView.swift – Apple TV search with real Jellyfin API
// ReelFin – tvOS 18+

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
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
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
        if item.mediaType == .episode, let seriesId = item.parentID {
            selectedItem = MediaItem(
                id: seriesId,
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
    @StateObject private var viewModel: TVSearchViewModel
    private let dependencies: ReelFinDependencies

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: TVSearchViewModel(dependencies: dependencies))
    }

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 28),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isSearching {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 40)
                Spacer()
            } else if viewModel.hasSearched && viewModel.results.isEmpty {
                emptyState
            } else if viewModel.results.isEmpty {
                browsePrompt
            } else {
                resultGrid
            }
        }
        .searchable(text: $viewModel.query, prompt: "Movies, Shows, Cast, Directors")
        .onChange(of: viewModel.query) { _, _ in
            viewModel.search()
        }
        .navigationTitle("Search")
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

    // MARK: - Browse Prompt

    @ViewBuilder
    private var browsePrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Search your library")
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)
            Text("No results for \"\(viewModel.query)\"")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Try a different search term.")
                .font(.body)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Result Grid

    @ViewBuilder
    private var resultGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 36) {
                ForEach(viewModel.results) { item in
                    TVSearchCardButton(
                        item: item,
                        dependencies: dependencies,
                        onSelect: { viewModel.select(item: $0) }
                    )
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
        }
        .focusSection()
    }
}

/// Focusable card for search results – uses the shared PosterCardArtworkView with real images.
private struct TVSearchCardButton: View {
    @FocusState private var isFocused: Bool

    let item: MediaItem
    let dependencies: ReelFinDependencies
    let onSelect: (MediaItem) -> Void

    var body: some View {
        Button {
            onSelect(item)
        } label: {
            PosterCardView(
                item: item,
                apiClient: dependencies.apiClient,
                imagePipeline: dependencies.imagePipeline,
                layoutStyle: .grid,
                titleLineLimit: 2
            )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
    }
}
#endif

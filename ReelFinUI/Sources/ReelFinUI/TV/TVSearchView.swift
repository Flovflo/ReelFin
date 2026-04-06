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
        VStack(alignment: .leading, spacing: 20) {
            Text("Search")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 18) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isSearchFieldFocused ? Color.black.opacity(0.86) : .white.opacity(0.72))
                    .frame(width: 58, height: 58)
                    .background { searchIconBackground }

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.20, blue: 0.22).opacity(isSearchFieldFocused ? 0.98 : 0.92))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(isSearchFieldFocused ? 0.12 : 0.06), lineWidth: 0.8)
                        }
                        .allowsHitTesting(false)

                    Text(searchDisplayText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(searchDisplayColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .allowsHitTesting(false)

                    TextField("", text: $viewModel.query)
                        .textFieldStyle(.plain)
                        .focused($isSearchFieldFocused)
                        .focusEffectDisabled(true)
                        .foregroundStyle(.clear)
                        .tint(.clear)
                        .opacity(0.18)
                        .submitLabel(.search)
                        .onMoveCommand { direction in
                            guard direction == .up else { return }
                            requestTopNavigationFocus?(.search)
                        }
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 22)
            .frame(width: 980, height: 104, alignment: .leading)
            .background { searchFieldBackground }
            .overlay { searchFieldStroke }
            .shadow(color: .black.opacity(isSearchFieldFocused ? 0.28 : 0.18), radius: isSearchFieldFocused ? 28 : 18, x: 0, y: isSearchFieldFocused ? 16 : 10)
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
    let item: MediaItem
    let dependencies: ReelFinDependencies
    let onSelect: (MediaItem) -> Void

    var body: some View {
        TVLibraryPosterCard(
            item: item,
            dependencies: dependencies,
            onFocus: { _ in },
            onSelect: onSelect
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
    }
}

private extension TVSearchView {
    @ViewBuilder
    var searchIconBackground: some View {
        if #available(tvOS 26.0, *) {
            Color.clear
                .glassEffect(
                    Glass.regular
                        .tint(Color.white.opacity(isSearchFieldFocused ? 0.30 : 0.10))
                        .interactive(),
                    in: .circle
                )
        } else {
            Circle()
                .fill(Color.white.opacity(isSearchFieldFocused ? 0.20 : 0.08))
        }
    }

    @ViewBuilder
    var searchFieldBackground: some View {
        if #available(tvOS 26.0, *) {
            Color.clear
                .glassEffect(
                    Glass.regular
                        .tint(Color.white.opacity(isSearchFieldFocused ? 0.18 : 0.07))
                        .interactive(),
                    in: .rect(cornerRadius: 30)
                )
        } else {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(ReelFinTheme.tvSurfaceMutedFill)
        }
    }

    var searchFieldStroke: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSearchFieldFocused ? 0.34 : 0.16),
                        Color.white.opacity(isSearchFieldFocused ? 0.16 : 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSearchFieldFocused ? 1.3 : 1
            )
    }

    var searchDisplayText: String {
        let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Movies, shows, cast, directors" : viewModel.query
    }

    var searchDisplayColor: Color {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .white.opacity(isSearchFieldFocused ? 0.62 : 0.42)
            : .white
    }
}
#endif

import Shared
import SwiftUI

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: LibraryViewModel
    private let dependencies: ReelFinDependencies

    init(dependencies: ReelFinDependencies) {
        _viewModel = StateObject(wrappedValue: LibraryViewModel(dependencies: dependencies))
        self.dependencies = dependencies
    }

    var body: some View {
        VStack(spacing: 14) {
            topBar

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(viewModel.items) { item in
                        Button {
                            viewModel.select(item: item)
                        } label: {
                            PosterCardView(
                                item: item,
                                apiClient: dependencies.apiClient,
                                imagePipeline: dependencies.imagePipeline,
                                layoutStyle: .grid
                            )
#if os(tvOS)
                            .scaleEffect(1.0) // scale handled by focus
#endif
                        }
                        .accessibilityIdentifier("media_card_button_\(item.id)")
                        .buttonStyle(.plain)
#if os(tvOS)
                        .hoverEffect(.highlight)
#endif
                        .task {
                            await viewModel.loadMoreIfNeeded(for: item)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 24)

                if viewModel.isLoadingPage {
                    ProgressView()
                        .tint(.white)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(ReelFinTheme.pageGradient.ignoresSafeArea())
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.selectedItem != nil },
                set: { if !$0 { viewModel.selectedItem = nil } }
            )
        ) {
            if let item = viewModel.selectedItem {
                DetailView(
                    dependencies: dependencies,
                    item: item
                )
            }
        }
        .task {
            await viewModel.loadInitial()
        }
        .onChange(of: viewModel.searchQuery) { _, _ in
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !Task.isCancelled {
                    await viewModel.searchChanged()
                }
            }
        }
        .onChange(of: viewModel.selectedFilter) { _, _ in
            Task { await viewModel.loadInitial() }
        }
        .onChange(of: viewModel.sortMode) { _, _ in
            Task { await viewModel.loadInitial() }
        }
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    @ViewBuilder
    private var topBar: some View {
#if os(tvOS)
        tvTopBar
#else
        iosTopBar
#endif
    }

    // MARK: - tvOS top bar: searchable + filter chips side by side

    private var tvTopBar: some View {
        HStack(spacing: 24) {
            Text("Library")
                .reelFinTitleStyle()

            Spacer()

            filterChip(title: "All", isActive: viewModel.selectedFilter == nil) {
                viewModel.selectedFilter = nil
            }
            filterChip(title: "Movies", isActive: viewModel.selectedFilter == .movie) {
                viewModel.selectedFilter = .movie
            }
            filterChip(title: "Shows", isActive: viewModel.selectedFilter == .series) {
                viewModel.selectedFilter = .series
            }

            Menu {
                Picker("Sort", selection: $viewModel.sortMode) {
                    ForEach(LibraryViewModel.SortMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(14)
                    .background(ReelFinTheme.card.opacity(0.9))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 8)
    }

    // MARK: - iOS top bar: full search bar + filter chips

    private var iosTopBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Library")
                    .reelFinTitleStyle()
                Spacer()

                Menu {
                    Picker("Sort", selection: $viewModel.sortMode) {
                        ForEach(LibraryViewModel.SortMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(10)
                        .background(ReelFinTheme.card.opacity(0.9))
                        .clipShape(Circle())
                }
            }

            HStack(spacing: 10) {
                filterChip(title: "All", isActive: viewModel.selectedFilter == nil) {
                    viewModel.selectedFilter = nil
                }
                filterChip(title: "Movies", isActive: viewModel.selectedFilter == .movie) {
                    viewModel.selectedFilter = .movie
                }
                filterChip(title: "Shows", isActive: viewModel.selectedFilter == .series) {
                    viewModel.selectedFilter = .series
                }
                Spacer()
            }

            TextField("Search your library", text: $viewModel.searchQuery)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(ReelFinTheme.card.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, horizontalPadding)
    }

    private func filterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: chipFontSize, weight: .semibold, design: .rounded))
                .padding(.horizontal, chipHPad)
                .padding(.vertical, chipVPad)
                .background(isActive ? ReelFinTheme.accent : ReelFinTheme.card.opacity(0.9))
                .clipShape(Capsule())
                .foregroundStyle(isActive ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }

    private var columns: [GridItem] {
#if os(tvOS)
        return [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 32)]
#else
        if horizontalSizeClass == .compact {
            return [GridItem(.adaptive(minimum: 152, maximum: 190), spacing: 12)]
        }
        return [GridItem(.adaptive(minimum: 186, maximum: 230), spacing: 16)]
#endif
    }

    private var gridSpacing: CGFloat {
#if os(tvOS)
        return 40
#else
        return 16
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        return 60
#else
        return horizontalSizeClass == .compact ? 12 : 22
#endif
    }

    private var chipFontSize: CGFloat {
#if os(tvOS)
        return 18
#else
        return 13
#endif
    }

    private var chipHPad: CGFloat {
#if os(tvOS)
        return 20
#else
        return 12
#endif
    }

    private var chipVPad: CGFloat {
#if os(tvOS)
        return 12
#else
        return 8
#endif
    }
}

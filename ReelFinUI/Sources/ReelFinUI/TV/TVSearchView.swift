// TVSearchView.swift – Apple TV search with controlled tvOS layout

#if os(tvOS)
import Shared
import SwiftUI
import UIKit

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
    @Environment(\.tvContentFocusReadyAction) private var notifyContentFocusReady
    @Environment(\.tvTopNavigationFocusAction) private var requestTopNavigationFocus
    @FocusState private var isSearchBarFocused: Bool
    @StateObject private var viewModel: TVSearchViewModel
    @State private var searchActivationToken = 0
    @State private var isSearchEditing = false
    @State private var lastHandledContentFocusSequence = 0
    private let dependencies: ReelFinDependencies
    private let contentFocusRequest: TVContentFocusRequest?

    init(dependencies: ReelFinDependencies) {
        self.init(dependencies: dependencies, contentFocusRequest: nil)
    }

    init(dependencies: ReelFinDependencies, contentFocusRequest: TVContentFocusRequest?) {
        self.dependencies = dependencies
        self.contentFocusRequest = contentFocusRequest
        _viewModel = StateObject(wrappedValue: TVSearchViewModel(dependencies: dependencies))
    }

    var body: some View {
        GeometryReader { proxy in
            let topRowItemIDs = TVAdaptiveGridFocusLayout(
                containerWidth: proxy.size.width,
                horizontalPadding: contentHorizontalPadding,
                minimumItemWidth: gridItemWidth,
                interItemSpacing: 22
            )
            .firstRowItemIDs(in: viewModel.results)

            VStack(alignment: .leading, spacing: 22) {
                searchHeader(containerWidth: proxy.size.width)
                searchContent(topRowItemIDs: topRowItemIDs)
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(searchScreenBackground.ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                hiddenSearchInput
            }
        }
        .onChange(of: viewModel.query) { _, _ in
            viewModel.search()
        }
        .onAppear {
            applyContentFocusRequestIfNeeded()
        }
        .onChange(of: contentFocusRequest?.sequence) { _, _ in
            applyContentFocusRequestIfNeeded()
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

    private func searchHeader(containerWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSearchChromeHighlighted ? .white.opacity(0.92) : .white.opacity(0.68))

            Text(searchDisplayText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(searchDisplayColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .frame(width: searchFieldWidth(for: containerWidth), height: 64, alignment: .leading)
        .background { searchFieldBackground }
        .overlay { searchFieldStroke }
        .shadow(
            color: .black.opacity(isSearchChromeHighlighted ? 0.18 : 0.10),
            radius: isSearchChromeHighlighted ? 18 : 12,
            x: 0,
            y: isSearchChromeHighlighted ? 10 : 7
        )
        .accessibilityIdentifier("tv_search_bar")
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .focusable(true, interactions: .activate)
        .focused($isSearchBarFocused)
        .focusEffectDisabled(true)
        .onTapGesture {
            activateSearch()
        }
        .onMoveCommand { direction in
            guard direction == .up else { return }
            requestTopNavigationFocus?(.search)
        }
        .animation(TVMotion.focusAnimation, value: isSearchChromeHighlighted)
    }

    @ViewBuilder
    private func searchContent(topRowItemIDs: Set<String>) -> some View {
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
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(viewModel.results) { item in
                        TVSearchCardButton(
                            item: item,
                            dependencies: dependencies,
                            onMoveUp: topRowItemIDs.contains(item.id) ? {
                                isSearchBarFocused = true
                            } : nil,
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
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .thin))
                .foregroundStyle(.white.opacity(0.38))
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
            Text(subtitle)
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 88)
    }
}

private struct TVSearchCardButton: View {
    let item: MediaItem
    let dependencies: ReelFinDependencies
    var onMoveUp: (() -> Void)? = nil
    let onSelect: (MediaItem) -> Void

    var body: some View {
        TVLibraryPosterCard(
            item: item,
            dependencies: dependencies,
            onFocus: { _ in },
            onMoveUp: onMoveUp,
            onSelect: onSelect
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
    }
}

private extension TVSearchView {
    var gridItemWidth: CGFloat {
        PosterCardMetrics.posterWidth(for: .grid, compact: false)
    }

    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: gridItemWidth, maximum: gridItemWidth + 18), spacing: 22)]
    }

    var contentHorizontalPadding: CGFloat {
        54
    }

    var hiddenSearchInput: some View {
        TVSearchKeyboardField(
            text: $viewModel.query,
            activationToken: searchActivationToken,
            isEditing: $isSearchEditing,
            onMoveUp: {
                requestTopNavigationFocus?(.search)
            }
        )
            .frame(width: 1, height: 1)
            .clipped()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .offset(x: -10_000, y: -10_000)
    }

    var searchScreenBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.010, green: 0.012, blue: 0.016),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottom
        )
    }

    var searchFieldBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(isSearchChromeHighlighted ? 0.065 : 0.040))
    }

    var searchFieldStroke: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSearchChromeHighlighted ? 0.16 : 0.10),
                        Color.white.opacity(isSearchChromeHighlighted ? 0.06 : 0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSearchChromeHighlighted ? 1.0 : 0.9
            )
    }

    func searchFieldWidth(for containerWidth: CGFloat) -> CGFloat {
        min(max(containerWidth * 0.44, 560), 800)
    }

    var searchDisplayText: String {
        let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Search movies, shows, cast" : viewModel.query
    }

    var searchDisplayColor: Color {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .white.opacity(isSearchChromeHighlighted ? 0.42 : 0.28)
            : .white.opacity(0.92)
    }

    var isSearchChromeHighlighted: Bool {
        isSearchBarFocused || isSearchEditing
    }

    func activateSearch() {
        isSearchBarFocused = true
        searchActivationToken += 1
    }

    func applyContentFocusRequestIfNeeded() {
        guard let contentFocusRequest else { return }
        guard contentFocusRequest.destination == .search else { return }
        guard contentFocusRequest.sequence != lastHandledContentFocusSequence else { return }

        lastHandledContentFocusSequence = contentFocusRequest.sequence
        isSearchBarFocused = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            notifyContentFocusReady?(.search, contentFocusRequest.sequence)
        }
    }
}

private struct TVSearchKeyboardField: UIViewRepresentable {
    @Binding var text: String
    let activationToken: Int
    @Binding var isEditing: Bool
    let onMoveUp: () -> Void

    func makeUIView(context: Context) -> TVSearchTextField {
        let textField = TVSearchTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.onMoveUp = onMoveUp
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.textColor = .clear
        textField.tintColor = .clear
        textField.returnKeyType = .search
        textField.enablesReturnKeyAutomatically = false
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        return textField
    }

    func updateUIView(_ uiView: TVSearchTextField, context: Context) {
        uiView.onMoveUp = onMoveUp
        if uiView.text != text {
            uiView.text = text
        }

        if context.coordinator.lastActivationToken != activationToken {
            context.coordinator.lastActivationToken = activationToken
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isEditing: $isEditing)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        @Binding private var isEditing: Bool
        var lastActivationToken = 0

        init(text: Binding<String>, isEditing: Binding<Bool>) {
            _text = text
            _isEditing = isEditing
        }

        @objc
        func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isEditing = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isEditing = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

private final class TVSearchTextField: UITextField {
    var onMoveUp: (() -> Void)?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .upArrow }) {
            onMoveUp?()
            return
        }

        super.pressesBegan(presses, with: event)
    }
}
#endif

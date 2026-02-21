import Shared
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: HomeViewModel
    @Namespace private var posterNamespace

    private let dependencies: ReelFinDependencies
    @State private var scrollInterval: SignpostInterval?

    init(dependencies: ReelFinDependencies) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(dependencies: dependencies))
        self.dependencies = dependencies
    }

    var body: some View {
        ZStack {
            ReelFinTheme.pageGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if viewModel.isInitialLoading && viewModel.feed.rows.isEmpty {
                        loadingSkeleton
                    } else if viewModel.feed.rows.allSatisfy({ $0.items.isEmpty }) && viewModel.feed.featured.isEmpty {
                        emptyState
                    } else {
                        featuredSection

                        ForEach(viewModel.feed.rows.filter { !$0.items.isEmpty }) { row in
                            homeRowView(row)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .refreshable {
                await viewModel.manualRefresh()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in
                        if scrollInterval == nil {
                            scrollInterval = SignpostInterval(signposter: Signpost.homeScroll, name: "home_scroll_session")
                        }
                    }
                    .onEnded { _ in
                        scrollInterval?.end(name: "home_scroll_session")
                        scrollInterval = nil
                    }
            )

            if let selectedItem = viewModel.selectedItem {
                DetailView(
                    dependencies: dependencies,
                    item: selectedItem,
                    namespace: posterNamespace,
                    onDismiss: {
                        viewModel.dismissDetail()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(3)
            }
        }
        .task {
            await viewModel.load()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Discover")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 10) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                }

                if viewModel.isRefreshing || viewModel.isInitialLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.leading, 6)
                }
            }

            Text("Featured")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)

            Text("Popular and trending movies")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, horizontalPadding)
    }

    @ViewBuilder
    private var featuredSection: some View {
        if !viewModel.feed.featured.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(viewModel.feed.featured.prefix(10)) { item in
                        featuredCard(for: item)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    private func featuredCard(for item: MediaItem) -> some View {
        Button {
            viewModel.select(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                CachedRemoteImage(
                    itemID: item.id,
                    type: .primary,
                    width: 460,
                    quality: 82,
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline
                )
                .frame(width: featuredCardWidth, height: featuredCardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.36), radius: 16, x: 0, y: 9)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

                Text(item.name)
                    .font(.system(size: 33, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
            }
            .frame(width: featuredCardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func homeRowView(_ row: HomeRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(row.items) { item in
                        Button {
                            viewModel.select(item: item)
                        } label: {
                            PosterCardView(
                                item: item,
                                apiClient: dependencies.apiClient,
                                imagePipeline: dependencies.imagePipeline,
                                namespace: namespaceForCard(itemID: item.id, rowID: row.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    private func namespaceForCard(itemID: String, rowID: String) -> Namespace.ID? {
        firstRowByItemID[itemID] == rowID ? posterNamespace : nil
    }

    private var firstRowByItemID: [String: String] {
        var map: [String: String] = [:]
        for row in viewModel.feed.rows {
            for item in row.items where map[item.id] == nil {
                map[item.id] = row.id
            }
        }
        return map
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(height: heroSkeletonHeight)
                .overlay(ShimmerView())
                .padding(.horizontal, horizontalPadding)

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 120, height: 24)
                        .padding(.horizontal, horizontalPadding)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(width: rowCardWidth, height: rowCardHeight)
                                    .overlay(ShimmerView())
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))

            Text("Your Home Is Ready")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("We could not load rows yet. Pull to refresh or update server settings.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                Task { await viewModel.manualRefresh() }
            } label: {
                Label("Retry Sync", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(ReelFinTheme.card.opacity(0.92))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 420 : 520)
        .padding(20)
        .background(ReelFinTheme.surface.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(ReelFinTheme.panelStroke, lineWidth: 1)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 10)
    }

    private var horizontalPadding: CGFloat {
        isCompact ? 14 : 22
    }

    private var isCompact: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var featuredCardWidth: CGFloat {
        isCompact ? 270 : 350
    }

    private var featuredCardHeight: CGFloat {
        featuredCardWidth * 1.45
    }

    private var heroSkeletonHeight: CGFloat {
        featuredCardHeight
    }

    private var rowCardWidth: CGFloat {
        isCompact ? 168 : 210
    }

    private var rowCardHeight: CGFloat {
        rowCardWidth * 1.5
    }
}

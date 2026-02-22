import Shared
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: HomeViewModel
    @Namespace private var posterNamespace

    private let dependencies: ReelFinDependencies
    @State private var scrollInterval: SignpostInterval?

    init(dependencies: ReelFinDependencies) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(dependencies: dependencies))
        self.dependencies = dependencies
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    if viewModel.isInitialLoading && viewModel.feed.rows.isEmpty {
                        loadingSkeleton
                            .padding(.top, 100)
                    } else if viewModel.feed.rows.allSatisfy({ $0.items.isEmpty }) && viewModel.feed.featured.isEmpty {
                        emptyState
                            .padding(.top, 100)
                    } else {
                        featuredSection

                        ForEach(viewModel.feed.rows.filter { !$0.items.isEmpty }) { row in
                            homeRowView(row)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 60) // Safety padding for the floating tab bar
            }
            .ignoresSafeArea(.container, edges: .top) // Let hero bleed to top edge
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

            .navigationDestination(
                isPresented: Binding(
                    get: { viewModel.selectedItem != nil },
                    set: { if !$0 { viewModel.selectedItem = nil } }
                )
            ) {
                if let item = viewModel.selectedItem {
                    DetailView(
                        dependencies: dependencies,
                        item: item,
                        namespace: posterNamespace
                    )
                }
            }
        .background(ReelFinTheme.pageGradient.ignoresSafeArea())
        .task {
            await viewModel.load()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var featuredSection: some View {
        if !viewModel.feed.featured.isEmpty {
            ZStack(alignment: .top) {
                HeroCarouselView(
                    items: Array(viewModel.feed.featured.prefix(10)),
                    apiClient: dependencies.apiClient,
                    imagePipeline: dependencies.imagePipeline,
                    onTap: { item in
                        viewModel.select(item: item)
                    }
                )

                // Top Chrome overlay (Home, Profile, Settings)
                topChrome
            }
        } else {
            topChrome
        }
    }

    private var topChrome: some View {
        HStack(alignment: .top) {
            Text("Home")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

            Spacer()

            HStack(spacing: 12) {
                if viewModel.isRefreshing || viewModel.isInitialLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 4)
                }

                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, horizontalPadding)
        // Add fixed top padding to account for dynamic island/safe area since we ignored it on the scroll container
        .padding(.top, 56)
    }

    private func homeRowView(_ row: HomeRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
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
                                layoutStyle: row.kind == .continueWatching ? .landscape : .row,
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



    private var heroSkeletonHeight: CGFloat {
        horizontalSizeClass == .compact ? 310 : 350
    }

    private var rowCardWidth: CGFloat {
        isCompact ? 168 : 210
    }

    private var rowCardHeight: CGFloat {
        rowCardWidth * 1.5
    }
}

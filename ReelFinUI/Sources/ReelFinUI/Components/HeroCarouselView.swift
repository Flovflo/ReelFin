import Shared
import SwiftUI

public struct HeroCarouselView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let items: [MediaItem]
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let onTap: (MediaItem) -> Void

    @State private var currentIndex: Int = 0

    public init(
        items: [MediaItem],
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        onTap: @escaping (MediaItem) -> Void
    ) {
        self.items = items
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.onTap = onTap
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ZStack(alignment: .bottom) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            heroContent(for: item)
                                .containerRelativeFrame(.horizontal)
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.98)
                                        .opacity(phase.isIdentity ? 1 : 0.8)
                                }
                                .id(index)
                                .onTapGesture {
                                    onTap(item)
                                }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: Binding(
                    get: { currentIndex },
                    set: { newIndex in if let idx = newIndex { currentIndex = idx } }
                ))
                .ignoresSafeArea(edges: .top)

                // Page Indicators (centered at the bottom)
                if items.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<items.count, id: \.self) { dotIndex in
                            Capsule()
                                .fill(currentIndex == dotIndex ? Color.white : Color.white.opacity(0.34))
                                .frame(width: currentIndex == dotIndex ? 24 : 8, height: 8)
                                .animation(.snappy(duration: 0.2), value: currentIndex)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .frame(height: heroHeight)
        }
    }

    @ViewBuilder
    private func heroContent(for item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            CachedRemoteImage(
                itemID: item.id,
                type: .backdrop,
                width: 1200,
                quality: 85,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
            .clipped()
            
            // Dark scrim to ensure text readability
            Rectangle()
                .fill(ReelFinTheme.heroGradientScrim)
            
            // Text & Buttons overlay
            VStack(alignment: .leading, spacing: 10) {
                if let badgeText = promoBadge(for: item) {
                    Text(badgeText)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassPanelStyle(cornerRadius: 8)
                }

                Text(item.name)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 36 : 48, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .accessibilityAddTraits(.isHeader)

                if !heroSubtitle(for: item).isEmpty {
                    Text(heroSubtitle(for: item))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }

                Text(heroMetadataText(for: item))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                heroActionButtons(for: item)
                    .padding(.top, 8)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heroActionButtons(for item: MediaItem) -> some View {
        HStack(spacing: 12) {
            Button {
                onTap(item)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .foregroundStyle(.black)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: currentIndex)

            Button {
                onTap(item)
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .frame(width: 52, height: 52)
                    .foregroundStyle(.white)
                    .glassPanelStyle(cornerRadius: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to Watchlist")
        }
    }

    private func promoBadge(for item: MediaItem) -> String? {
        if item.mediaType == .series {
            return "Series"
        }
        if item.mediaType == .episode {
            return "New Episode"
        }
        return nil
    }

    private func heroSubtitle(for item: MediaItem) -> String {
        let genreText = item.genres.prefix(2).joined(separator: " • ")
        return genreText
    }

    private func heroMetadataText(for item: MediaItem) -> String {
        var entries: [String] = []
        if let year = item.year {
            entries.append(String(year))
        }
        if let runtime = item.runtimeMinutes {
            entries.append("\(runtime)m")
        }
        return entries.joined(separator: " • ")
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 24 : 40
    }

    private var heroHeight: CGFloat {
        if horizontalSizeClass == .compact {
            return dynamicTypeSize.isAccessibilitySize ? 620 : 540
        }
        return dynamicTypeSize.isAccessibilitySize ? 720 : 660
    }
}

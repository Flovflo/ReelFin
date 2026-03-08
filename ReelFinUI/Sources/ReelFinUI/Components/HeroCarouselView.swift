import Combine
import Shared
import SwiftUI

public struct HeroCarouselView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    private let items: [MediaItem]
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let onTap: (MediaItem) -> Void

    @State private var currentIndex: Int = 0
    private let timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

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
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    TabView(selection: Binding(
                        get: { currentIndex },
                        set: { newIndex in currentIndex = newIndex }
                    )) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                onTap(item)
                            } label: {
                                heroContent(for: item, size: proxy.size)
                                    .frame(width: proxy.size.width, height: heroHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .tag(index)
                            .accessibilityLabel(item.name)
                            .accessibilityAddTraits(.isButton)
                            .clipped()
                            .containerRelativeFrame(.horizontal)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: proxy.size.width, height: heroHeight)
                    .ignoresSafeArea(edges: .top)
                    .clipped()

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
                .frame(width: proxy.size.width, height: heroHeight, alignment: .bottom)
            }
            .frame(height: heroHeight)
            .onReceive(timer) { _ in
                if items.count > 1 {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        currentIndex = (currentIndex + 1) % items.count
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func heroContent(for item: MediaItem, size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            Color.black

            CachedRemoteImage(
                itemID: item.id,
                type: .backdrop,
                width: backdropImageWidth(for: size),
                quality: 85,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
            .frame(width: size.width, height: heroHeight)
            .clipped()
            
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black.opacity(0.45), location: 0.5),
                            .init(color: .black.opacity(0.92), location: 0.78),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Text & Buttons overlay
            VStack(alignment: .center, spacing: 12) {
                if let badgeText = promoBadge(for: item) {
                    Text(badgeText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassPanelStyle(cornerRadius: 8)
                }

                Text(item.name)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 32 : 44, weight: .heavy, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .accessibilityAddTraits(.isHeader)

                Text(heroMetadataText(for: item))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                heroActionButtons(for: item)
                    .padding(.top, 12)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 60)
            .frame(width: max(size.width - (horizontalPadding * 2), 0), alignment: .center)
        }
        .frame(width: size.width, height: heroHeight)
        .clipped()
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
        
        let typeStr = item.mediaType == .series ? "TV Show" : "Movie"
        entries.append(typeStr)

        if !item.genres.isEmpty {
            entries.append(item.genres.prefix(2).joined(separator: " • "))
        }
        
        return entries.joined(separator: " • ")
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 32 : 48
    }

    private var heroHeight: CGFloat {
        if horizontalSizeClass == .compact {
            return dynamicTypeSize.isAccessibilitySize ? 620 : 540
        }
        return dynamicTypeSize.isAccessibilitySize ? 720 : 660
    }

    private func backdropImageWidth(for size: CGSize) -> Int {
        let requestedWidth = Int((size.width * displayScale).rounded(.up))
        return min(max(requestedWidth, 720), 1400)
    }
}

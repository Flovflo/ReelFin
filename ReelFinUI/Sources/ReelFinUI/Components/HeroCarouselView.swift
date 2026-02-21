import Shared
import SwiftUI

public struct HeroCarouselView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let items: [MediaItem]
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let onTap: (MediaItem) -> Void

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
        TabView {
            ForEach(items) { item in
                Button {
                    onTap(item)
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        CachedRemoteImage(
                            itemID: item.id,
                            type: .backdrop,
                            width: 1200,
                            quality: 80,
                            apiClient: apiClient,
                            imagePipeline: imagePipeline
                        )
                        .overlay(ReelFinTheme.heroGradient)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .lineLimit(2)
                                .foregroundStyle(.white)

                            if let summary = item.overview, !summary.isEmpty {
                                Text(summary)
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .lineLimit(3)
                                    .foregroundStyle(.white.opacity(0.82))
                            }

                            HStack(spacing: 10) {
                                Label("Play", systemImage: "play.fill")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.92))
                                    .foregroundStyle(.black)
                                    .clipShape(Capsule())

                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .padding(10)
                                    .background(.white.opacity(0.22))
                                    .clipShape(Circle())
                            }
                            .padding(.top, 4)
                        }
                        .padding(20)
                    }
                    .frame(height: heroHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: heroHeight + 10)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    private var heroHeight: CGFloat {
        horizontalSizeClass == .compact ? 310 : 350
    }
}

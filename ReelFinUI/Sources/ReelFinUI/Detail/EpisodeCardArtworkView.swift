import ImageCache
import JellyfinAPI
import Shared
import SwiftUI

struct EpisodeCardArtworkView: View {
    let episode: MediaItem
    let width: CGFloat
    let height: CGFloat?
    let cornerRadius: CGFloat?
    let showsRuntimeBadge: Bool
    let showsProgressBar: Bool
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    init(
        episode: MediaItem,
        width: CGFloat,
        height: CGFloat? = nil,
        cornerRadius: CGFloat? = nil,
        showsRuntimeBadge: Bool = true,
        showsProgressBar: Bool = true,
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.episode = episode
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.showsRuntimeBadge = showsRuntimeBadge
        self.showsProgressBar = showsProgressBar
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
    }

    private var artworkHeight: CGFloat { height ?? (width * 0.56) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedRemoteImage(
                itemID: episode.id,
                type: .primary,
                width: Int(width * 2),
                quality: 80,
                contentMode: .fill,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
            .frame(width: width, height: artworkHeight)
            .clipped()

            // Subtle bottom gradient for badge readability
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.05), location: 0.45),
                    .init(color: .black.opacity(0.45), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // ── Runtime badge (play ▶ Xm) — bottom-left ────────────────────
            if showsRuntimeBadge, let runtime = episode.runtimeDisplayText {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: runtimeIconSize, weight: .bold))
                    Text(runtime)
                        .font(.system(size: runtimeFontSize, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.40), in: Capsule(style: .continuous))
                .padding(runtimeBadgePadding)
            }

            // ── Progress bar — thin, at very bottom ─────────────────────────
            if showsProgressBar, let progress = episode.playbackProgress, progress > 0, !episode.isPlayed {
                VStack {
                    Spacer()
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.white.opacity(0.20))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.88))
                                    .frame(width: proxy.size.width * CGFloat(progress))
                            }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(width: width, height: artworkHeight)
        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
    }

    private var artworkCornerRadius: CGFloat {
        if let cornerRadius {
            return cornerRadius
        }

        #if os(tvOS)
        return 16
        #else
        return 28
        #endif
    }

    private var runtimeIconSize: CGFloat {
        #if os(tvOS)
        return 12
        #else
        return 10
        #endif
    }

    private var runtimeFontSize: CGFloat {
        #if os(tvOS)
        return 16
        #else
        return 13
        #endif
    }

    private var runtimeBadgePadding: CGFloat {
        #if os(tvOS)
        return 16
        #else
        return 14
        #endif
    }
}

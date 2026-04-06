import ImageCache
import JellyfinAPI
import Shared
import SwiftUI

public struct EpisodeCardView: View {
    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #else
    @Environment(\.isFocused) private var isFocused
    #endif

    let episode: MediaItem
    let width: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onMoveUp: (() -> Void)?
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    public init(
        episode: MediaItem,
        width: CGFloat,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void,
        onMoveUp: (() -> Void)? = nil,
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.episode = episode
        self.width = width
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onMoveUp = onMoveUp
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        #if os(tvOS)
        tvBody
        #else
        iosBody
        #endif
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: tvOS — native Apple TV+ style
    //
    // Custom focusable card to avoid the oversized system focus container.
    // ─────────────────────────────────────────────────────────────────────────
    #if os(tvOS)
    private var tvBody: some View {
        ZStack(alignment: .bottomLeading) {
            tvArtworkLayer
            tvOverlayGradient
            tvTextOverlay
        }
        .frame(width: width, height: tvCardHeight, alignment: .leading)
        .background(Color.white.opacity(0.03), in: tvCardShape)
        .overlay {
            tvCardShape
                .stroke(
                    Color.white.opacity(isFocused ? 0.18 : (isSelected ? 0.16 : 0.08)),
                    lineWidth: isFocused ? 1.2 : 0.9
                )
        }
        .clipShape(tvCardShape)
        .contentShape(tvCardShape)
        .tvMotionFocus(.episodeCard, isFocused: isFocused)
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.18), radius: isFocused ? 24 : 14, x: 0, y: isFocused ? 14 : 8)
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: onSelect)
        .onMoveCommand { direction in
            guard direction == .up else { return }
            onMoveUp?()
        }
        .animation(.smooth(duration: 0.20, extraBounce: 0.01), value: isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Play episode")
        .accessibilityValue(tvEpisodeAccessibilityStatus)
    }

    private var tvEpisodeLabel: String {
        if let num = episode.indexNumber {
            return "Episode \(num)"
        }
        return "Episode"
    }

    private var tvArtworkLayer: some View {
        EpisodeCardArtworkView(
            episode: episode,
            width: width,
            height: tvCardHeight,
            cornerRadius: 30,
            showsRuntimeBadge: false,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
    }

    private var tvOverlayGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.08),
                .init(color: .black.opacity(0.10), location: 0.30),
                .init(color: .black.opacity(0.42), location: 0.56),
                .init(color: .black.opacity(0.82), location: 0.82),
                .init(color: .black.opacity(0.96), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var tvTextOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(tvEpisodeLabel.uppercased())
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(isFocused ? 0.78 : 0.62))

                Spacer(minLength: 0)

                tvPlaybackStatusBadge
            }

            Text(episode.name)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(isFocused ? 0.82 : 0.72))
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                if let runtime = episode.runtimeDisplayText {
                    Label(runtime, systemImage: "play.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var tvCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
    }

    @ViewBuilder
    private var tvPlaybackStatusBadge: some View {
        if episode.isPlayed {
            EpisodePlaybackStatusBadge(
                text: "Watched",
                systemImage: "checkmark.circle.fill",
                tint: Color(red: 0.78, green: 0.95, blue: 0.82)
            )
        } else if let positionText = episode.playbackPositionDisplayText {
            EpisodePlaybackStatusBadge(
                text: positionText,
                systemImage: "play.circle.fill",
                tint: Color.white.opacity(0.92)
            )
        }
    }

    private var tvEpisodeAccessibilityStatus: String {
        if episode.isPlayed {
            return "Watched"
        }
        if let positionText = episode.playbackPositionDisplayText {
            return "Stopped at \(positionText)"
        }
        return "Not started"
    }

    private var tvCardHeight: CGFloat { width * 0.98 }
    #endif

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: iOS
    // ─────────────────────────────────────────────────────────────────────────
    #if !os(tvOS)
    private var iosBody: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                CachedRemoteImage(
                    itemID: episode.id,
                    type: .primary,
                    width: Int(width * 2),
                    quality: 84,
                    contentMode: .fill,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline
                )
                .frame(width: width, height: iosCardHeight)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.10),
                        .init(color: .black.opacity(0.10), location: 0.34),
                        .init(color: .black.opacity(0.46), location: 0.58),
                        .init(color: .black.opacity(0.84), location: 0.80),
                        .init(color: .black.opacity(0.94), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let progress = episode.playbackProgress, progress > 0, !episode.isPlayed {
                    VStack {
                        Spacer()
                        GeometryReader { proxy in
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.18))
                                .overlay(alignment: .leading) {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.92))
                                        .frame(width: proxy.size.width * CGFloat(progress))
                                }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(iosEpisodeLabel.uppercased())
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.76))

                        Spacer(minLength: 0)

                        playbackStatusBadge
                    }

                    Text(episode.name)
                        .font(.system(size: 21, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(4)
                    }

                    HStack(spacing: 8) {
                        if let runtime = episode.runtimeDisplayText {
                            Label(runtime, systemImage: "play.fill")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(width: width, height: iosCardHeight, alignment: .leading)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        Color.white.opacity(isSelected ? 0.22 : 0.08),
                        lineWidth: isSelected ? 1.0 : 0.8
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.20), radius: isFocused ? 22 : 14, x: 0, y: isFocused ? 12 : 8)
        .scaleEffect(isFocused ? 1.018 : 1)
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .accessibilityHint("Play episode")
        .accessibilityValue(episodeAccessibilityStatus)
    }

    private var iosEpisodeLabel: String {
        if let index = episode.indexNumber {
            return "Episode \(index)"
        }
        return "Episode"
    }

    @ViewBuilder
    private var playbackStatusBadge: some View {
        if episode.isPlayed {
            EpisodePlaybackStatusBadge(
                text: "Watched",
                systemImage: "checkmark.circle.fill",
                tint: Color(red: 0.78, green: 0.95, blue: 0.82)
            )
        } else if let positionText = episode.playbackPositionDisplayText {
            EpisodePlaybackStatusBadge(
                text: "Stopped \(positionText)",
                systemImage: "play.circle.fill",
                tint: Color.white.opacity(0.92)
            )
        }
    }

    private var episodeAccessibilityStatus: String {
        if episode.isPlayed {
            return "Watched"
        }
        if let positionText = episode.playbackPositionDisplayText {
            return "Stopped at \(positionText)"
        }
        return "Not started"
    }

    private var iosCardHeight: CGFloat { width * 1.14 }
    #endif
}

private struct EpisodePlaybackStatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: horizontalSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .bold))

            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(Color.black.opacity(0.24), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: strokeWidth)
        }
    }

    private var iconSize: CGFloat {
#if os(tvOS)
        11
#else
        10
#endif
    }

    private var fontSize: CGFloat {
#if os(tvOS)
        12
#else
        11
#endif
    }

    private var horizontalSpacing: CGFloat {
#if os(tvOS)
        7
#else
        6
#endif
    }

    private var horizontalPadding: CGFloat {
#if os(tvOS)
        10
#else
        9
#endif
    }

    private var verticalPadding: CGFloat {
#if os(tvOS)
        6
#else
        5
#endif
    }

    private var strokeWidth: CGFloat {
#if os(tvOS)
        0.9
#else
        0.8
#endif
    }
}

#Preview("Episode Card - TV", traits: .fixedLayout(width: 560, height: 520)) {
    ZStack {
        ReelFinTheme.pageGradient.ignoresSafeArea()
        EpisodeCardView(
            episode: MediaItem(
                id: "episode-preview",
                name: "A House Divided",
                overview: "The crew finally gets close to the vault, but the cost of the mission starts to fracture the team.",
                mediaType: .episode,
                year: 2026,
                runtimeTicks: Int64(48 * 60 * 10_000_000),
                genres: ["Drama"],
                communityRating: 8.4,
                posterTag: "poster",
                backdropTag: "backdrop",
                libraryID: "shows",
                parentID: "series-1",
                indexNumber: 5,
                parentIndexNumber: 2,
                playbackPositionTicks: Int64(20 * 60 * 10_000_000)
            ),
            width: 470,
            isSelected: true,
            onSelect: {},
            apiClient: ReelFinPreviewFactory.dependencies().apiClient,
            imagePipeline: ReelFinPreviewFactory.dependencies().imagePipeline
        )
    }
}

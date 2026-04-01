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
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

    public init(
        episode: MediaItem,
        width: CGFloat,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void,
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol
    ) {
        self.episode = episode
        self.width = width
        self.isSelected = isSelected
        self.onSelect = onSelect
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
        VStack(alignment: .leading, spacing: 14) {
            EpisodeCardArtworkView(
                episode: episode,
                width: width,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(tvEpisodeLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(isFocused ? 0.72 : 0.50))
                    .textCase(.uppercase)

                Text(episode.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.92))
                    .lineLimit(2)

                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(isFocused ? 0.70 : 0.50))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: width, alignment: .leading)
        .scaleEffect(isFocused ? 1.045 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.18), radius: isFocused ? 26 : 12, x: 0, y: isFocused ? 16 : 8)
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onTapGesture(perform: onSelect)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Play episode")
    }

    private var tvEpisodeLabel: String {
        if let num = episode.indexNumber {
            return "Episode \(num)"
        }
        return "Episode"
    }
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
                    Text(iosEpisodeLabel.uppercased())
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))

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
    }

    private var iosEpisodeLabel: String {
        if let index = episode.indexNumber {
            return "Episode \(index)"
        }
        return "Episode"
    }

    private var iosCardHeight: CGFloat { width * 1.14 }
    #endif
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

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
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    EpisodeCardArtworkView(
                        episode: episode,
                        width: width,
                        apiClient: apiClient,
                        imagePipeline: imagePipeline
                    )

                    HStack(spacing: 10) {
                        statusBadge(
                            title: iosEpisodeLabel,
                            systemImage: isSelected ? "play.fill" : nil,
                            prominent: isSelected
                        )
                    }
                    .padding(18)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(episode.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isSelected {
                            Text("Current")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.20),
                                            Color.white.opacity(0.10)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: Capsule(style: .continuous)
                                )
                        }
                    }

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
            .tvCardSurface(focused: isFocused, selected: isSelected, cornerRadius: 28)
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
        let seasonText = episode.parentIndexNumber.map { "S\($0)" } ?? ""
        let episodeText = episode.indexNumber.map { "E\($0)" } ?? "Episode"
        return "\(seasonText) \(episodeText)".trimmingCharacters(in: .whitespaces)
    }

    private func statusBadge(title: String, systemImage: String? = nil, prominent: Bool) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(prominent ? 0.96 : 0.84))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(prominent ? 0.50 : 0.38),
                    Color.black.opacity(prominent ? 0.26 : 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(prominent ? 0.18 : 0.10), lineWidth: 1)
        }
    }
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

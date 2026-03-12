import ImageCache
import JellyfinAPI
import Shared
import SwiftUI

struct EpisodeCardArtworkView: View {
    let episode: MediaItem
    let width: CGFloat
    let selectionLabel: String?
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol

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
            .frame(width: width, height: width * 0.56)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.10), location: 0.58),
                    .init(color: .black.opacity(0.68), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if episode.isPlayed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(16)
                    .accessibilityHidden(true)
            }

            if let selectionLabel {
                Text(selectionLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.88))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
                    .padding(16)
                    .accessibilityHidden(true)
            }

            if let progress = episode.playbackProgress, progress > 0, !episode.isPlayed {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.white)
                                .frame(width: proxy.size.width * CGFloat(progress))
                        }
                }
                .frame(height: 4)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .frame(width: width, height: width * 0.56)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

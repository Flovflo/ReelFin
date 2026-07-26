import Shared
import SwiftUI

struct CinematicBackdropView: View {
    let item: MediaItem?
    let fallbackItem: MediaItem?
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    var sharpnessOpacity: Double = 0.84
    var blurOpacity: Double = 0.52
    var bottomFadeStart: Double = 0.58
    var leadingScrimOpacity: Double = 0.82
    var edgeVignetteOpacity: Double = 0.58
    var onHeroImageVisible: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                baseGradient

                if let displayedItem {
                    backdropLayer(for: displayedItem, size: proxy.size)
                }

                overlayWash
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    private var baseGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.02, blue: 0.04),
                    Color(red: 0.03, green: 0.05, blue: 0.09),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 80,
                endRadius: 680
            )
        }
    }

    private func backdropLayer(for item: MediaItem, size: CGSize) -> some View {
        ZStack {
            CachedRemoteImage(
                request: ArtworkRequest.make(for: item, role: .heroLow),
                contentMode: .fill,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
            .frame(width: size.width * 1.42, height: size.height * 1.18)
            .scaleEffect(1.16)
            .blur(radius: 44)
            .saturation(1.08)
            .opacity(blurOpacity + 0.08)

            CachedRemoteImage(
                request: ArtworkRequest.make(for: item, role: .heroHigh),
                contentMode: .fill,
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                onImageLoaded: onHeroImageVisible
            )
            .frame(width: size.width * 1.3, height: size.height * 1.1)
            .scaleEffect(1.08)
            .opacity(sharpnessOpacity)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.5), location: 0.0),
                        .init(color: .clear, location: 0.16),
                        .init(color: .clear, location: 0.84),
                        .init(color: .black.opacity(0.5), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var overlayWash: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(leadingScrimOpacity), location: 0.0),
                    .init(color: Color.black.opacity(leadingScrimOpacity * 0.56), location: 0.18),
                    .init(color: Color.black.opacity(0.12), location: 0.42),
                    .init(color: .clear, location: 0.66)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(edgeVignetteOpacity), location: 0.0),
                    .init(color: .clear, location: 0.1),
                    .init(color: .clear, location: 0.9),
                    .init(color: Color.black.opacity(edgeVignetteOpacity), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.08), location: 0.0),
                    .init(color: .clear, location: 0.16),
                    .init(color: .clear, location: bottomFadeStart),
                    .init(color: Color.black.opacity(0.92), location: 0.92),
                    .init(color: Color.black, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

        }
    }

    private var displayedItem: MediaItem? {
        switch CinematicBackdropLayerPolicy.source(
            hasItem: item != nil,
            hasFallbackItem: fallbackItem != nil
        ) {
        case .item:
            return item
        case .fallback:
            return fallbackItem
        case .none:
            return nil
        }
    }
}

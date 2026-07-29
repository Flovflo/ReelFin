import Shared
import SwiftUI

public enum CachedRemoteImageContentMode: Sendable {
    case fill
    case fit
}

public struct CachedRemoteImage: View {
    private let itemID: String
    private let type: JellyfinImageType
    private let width: Int
    private let quality: Int
    private let contentMode: CachedRemoteImageContentMode
    private let onImageLoaded: (() -> Void)?
    private let placeholderAnimationEnabled: Bool
    private let showsPlaceholder: Bool

    @StateObject private var loader: CachedRemoteImageLoader

    public init(
        request: ArtworkRequest,
        contentMode: CachedRemoteImageContentMode = .fill,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        showsPlaceholder: Bool = true,
        onImageLoaded: (() -> Void)? = nil
    ) {
        itemID = request.itemID
        type = request.type
        width = request.profile.width
        quality = request.profile.quality
        self.contentMode = contentMode
        self.onImageLoaded = onImageLoaded
        placeholderAnimationEnabled = ShimmerAnimationPolicy.animationEnabled(
            for: request.profile
        )
        self.showsPlaceholder = showsPlaceholder
        _loader = StateObject(
            wrappedValue: CachedRemoteImageLoader(apiClient: apiClient, imagePipeline: imagePipeline)
        )
    }

    public init(
        itemID: String,
        type: JellyfinImageType,
        width: Int,
        quality: Int = 82,
        contentMode: CachedRemoteImageContentMode = .fill,
        placeholderAnimationEnabled: Bool = false,
        showsPlaceholder: Bool = true,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        onImageLoaded: (() -> Void)? = nil
    ) {
        self.itemID = itemID
        self.type = type
        self.width = width
        self.quality = quality
        self.contentMode = contentMode
        self.onImageLoaded = onImageLoaded
        self.placeholderAnimationEnabled = placeholderAnimationEnabled
        self.showsPlaceholder = showsPlaceholder
        _loader = StateObject(
            wrappedValue: CachedRemoteImageLoader(apiClient: apiClient, imagePipeline: imagePipeline)
        )
    }

    public var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .modifier(RemoteImageScalingModifier(contentMode: contentMode))
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else if loader.hasFailed, showsPlaceholder {
                MissingArtworkView(seed: itemID)
                    .transition(.opacity.animation(.easeOut(duration: 0.16)))
            } else if showsPlaceholder {
                ShimmerView(animationEnabled: placeholderAnimationEnabled)
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            } else {
                Color.clear
            }
        }
        .clipped()
        .task(id: requestIdentity) {
            await loader.load(descriptor: descriptor, onImageLoaded: onImageLoaded)
        }
        .onDisappear {
            loader.invalidate()
        }
    }

    private var descriptor: CachedRemoteImageDescriptor {
        CachedRemoteImageDescriptor(
            itemID: itemID,
            type: type,
            width: normalizedWidth,
            quality: quality
        )
    }

    private var requestIdentity: String {
        "\(itemID)-\(type.rawValue)-\(normalizedWidth)-\(quality)-\(contentMode.identity)"
    }

    private var normalizedWidth: Int {
        type.normalizedImageWidth(width)
    }
}

private struct MissingArtworkView: View {
    let seed: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.28, brightness: 0.22),
                    Color(hue: shiftedHue, saturation: 0.18, brightness: 0.09),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [.white.opacity(0.11), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 260
            )

            Image(systemName: "film.stack")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .accessibilityHidden(true)
        }
    }

    private var hue: Double {
        Double(stableSeed % 360) / 360
    }

    private var shiftedHue: Double {
        (hue + 0.08).truncatingRemainder(dividingBy: 1)
    }

    private var stableSeed: UInt64 {
        seed.utf8.reduce(5381) { partial, byte in
            ((partial << 5) &+ partial) &+ UInt64(byte)
        }
    }
}

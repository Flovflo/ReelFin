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

    @StateObject private var loader: CachedRemoteImageLoader

    public init(
        request: ArtworkRequest,
        contentMode: CachedRemoteImageContentMode = .fill,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
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
            } else {
                ShimmerView(animationEnabled: placeholderAnimationEnabled)
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
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

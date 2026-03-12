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
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let onImageLoaded: (() -> Void)?

    @State private var image: UIImage?
    @State private var requestURL: URL?

    public init(
        itemID: String,
        type: JellyfinImageType,
        width: Int,
        quality: Int = 82,
        contentMode: CachedRemoteImageContentMode = .fill,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        onImageLoaded: (() -> Void)? = nil
    ) {
        self.itemID = itemID
        self.type = type
        self.width = width
        self.quality = quality
        self.contentMode = contentMode
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.onImageLoaded = onImageLoaded
    }

    public var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .modifier(RemoteImageScalingModifier(contentMode: contentMode))
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                ShimmerView()
                    .overlay {
                        Image(systemName: "film")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
            }
        }
        .clipped()
        .task(id: requestIdentity) {
            await load()
        }
        .onDisappear {
            if let requestURL {
                imagePipeline.cancel(url: requestURL)
            }
        }
    }

    private func load() async {
        if let requestURL {
            imagePipeline.cancel(url: requestURL)
        }
        requestURL = nil
        image = nil

        guard let url = await apiClient.imageURL(for: itemID, type: type, width: width, quality: quality) else {
            return
        }

        requestURL = url

        if let cached = await imagePipeline.cachedImage(for: url) {
            image = cached
            onImageLoaded?()
            return
        }

        do {
            let downloaded = try await imagePipeline.image(for: url)
            image = downloaded
            onImageLoaded?()
        } catch {
            if shouldIgnoreImageError(error) {
                return
            }

            // Fallback path: when poster/backdrop is missing, try the opposite type once.
            if let fallbackType = fallbackType(for: type),
               let fallbackURL = await apiClient.imageURL(for: itemID, type: fallbackType, width: width, quality: quality) {
                do {
                    let fallbackImage = try await imagePipeline.image(for: fallbackURL)
                    image = fallbackImage
                    onImageLoaded?()
                    return
                } catch {
                    if shouldIgnoreImageError(error) {
                        return
                    }
                }
            }

            AppLog.caching.error("Image load failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private var requestIdentity: String {
        "\(itemID)-\(type.rawValue)-\(width)-\(quality)-\(contentMode.identity)"
    }

    private func fallbackType(for sourceType: JellyfinImageType) -> JellyfinImageType? {
        switch sourceType {
        case .primary:
            return .backdrop
        case .backdrop:
            return .primary
        case .logo:
            return nil
        }
    }

    private func shouldIgnoreImageError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("404")
    }
}

private extension CachedRemoteImageContentMode {
    var identity: String {
        switch self {
        case .fill:
            return "fill"
        case .fit:
            return "fit"
        }
    }
}

private struct RemoteImageScalingModifier: ViewModifier {
    let contentMode: CachedRemoteImageContentMode

    func body(content: Content) -> some View {
        switch contentMode {
        case .fill:
            content.scaledToFill()
        case .fit:
            content.scaledToFit()
        }
    }
}

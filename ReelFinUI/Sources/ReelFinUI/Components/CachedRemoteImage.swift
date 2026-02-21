import Shared
import SwiftUI

public struct CachedRemoteImage: View {
    private let itemID: String
    private let type: JellyfinImageType
    private let width: Int
    private let quality: Int
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol

    @State private var image: UIImage?
    @State private var requestURL: URL?

    public init(
        itemID: String,
        type: JellyfinImageType,
        width: Int,
        quality: Int = 82,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol
    ) {
        self.itemID = itemID
        self.type = type
        self.width = width
        self.quality = quality
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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
        .task(id: itemID) {
            await load()
        }
        .onDisappear {
            if let requestURL {
                imagePipeline.cancel(url: requestURL)
            }
        }
    }

    private func load() async {
        guard let url = await apiClient.imageURL(for: itemID, type: type, width: width, quality: quality) else {
            return
        }

        requestURL = url

        if let cached = await imagePipeline.cachedImage(for: url) {
            image = cached
            return
        }

        do {
            let downloaded = try await imagePipeline.image(for: url)
            image = downloaded
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

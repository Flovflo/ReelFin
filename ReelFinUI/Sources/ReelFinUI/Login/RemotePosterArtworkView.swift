#if os(iOS) || os(tvOS)
import Shared
import SwiftUI
import UIKit

struct RemotePosterArtworkView: View {
    private enum Source {
        case bundled(String)
        case remote(URL, any ImagePipelineProtocol)
    }

    private let source: Source

    @State private var image: UIImage?
    @State private var loadedURL: URL?

    init(resourceName: String) {
        source = .bundled(resourceName)
    }

    init(url: URL, imagePipeline: any ImagePipelineProtocol) {
        source = .remote(url, imagePipeline)
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let bundledImage {
                    posterSurface(for: bundledImage, in: proxy.size)
                } else if let image {
                    posterSurface(for: image, in: proxy.size)
                        .transition(.opacity.animation(.easeInOut(duration: 0.22)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: remoteIdentity) {
            await loadRemote()
        }
        .onDisappear {
            guard case let .remote(url, imagePipeline) = source else {
                return
            }
            imagePipeline.cancel(url: url)
        }
    }

    private func loadRemote() async {
        guard case let .remote(url, imagePipeline) = source else {
            return
        }

        if loadedURL != url {
            loadedURL = url
            await MainActor.run {
                image = nil
            }
        }

        if let cached = await imagePipeline.cachedImage(for: url) {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) {
                    image = cached
                }
            }
            return
        }

        guard let downloaded = try? await imagePipeline.image(for: url) else {
            return
        }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.22)) {
                image = downloaded
            }
        }
    }

    private var bundledImage: UIImage? {
        guard case let .bundled(resourceName) = source else {
            return nil
        }

        return bundledImage(named: resourceName)
    }

    private var remoteIdentity: String {
        switch source {
        case .bundled:
            return "bundle"
        case let .remote(url, _):
            return url.absoluteString
        }
    }

    @ViewBuilder
    private func posterSurface(for image: UIImage, in size: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .saturation(1.02)
            .contrast(1.02)
    }

    private func bundledImage(named resourceName: String) -> UIImage? {
        let resourceURL: URL?

        if let directURL = Bundle.main.url(forResource: resourceName, withExtension: nil) {
            resourceURL = directURL
        } else {
            let nsName = resourceName as NSString
            resourceURL = Bundle.main.url(
                forResource: nsName.deletingPathExtension,
                withExtension: nsName.pathExtension.isEmpty ? nil : nsName.pathExtension
            )
        }

        guard let resourceURL else {
            return nil
        }

        return UIImage(contentsOfFile: resourceURL.path)
    }
}
#endif

import Shared
import SwiftUI

public enum PosterCardLayoutStyle: Sendable {
    case row
    case grid
}

public struct PosterCardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let item: MediaItem
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let layoutStyle: PosterCardLayoutStyle
    private let namespace: Namespace.ID?

    public init(
        item: MediaItem,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        layoutStyle: PosterCardLayoutStyle = .row,
        namespace: Namespace.ID? = nil
    ) {
        self.item = item
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.layoutStyle = layoutStyle
        self.namespace = namespace
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedRemoteImage(
                itemID: item.id,
                type: .primary,
                width: 360,
                apiClient: apiClient,
                imagePipeline: imagePipeline
            )
            .frame(width: posterWidth, height: posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
            .modifier(MatchedCardModifier(itemID: item.id, namespace: namespace))

            Text(item.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let year = item.year {
                Text(String(year))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: posterWidth + 2, alignment: .leading)
    }

    private var posterWidth: CGFloat {
        switch layoutStyle {
        case .row:
            return horizontalSizeClass == .compact ? 168 : 210
        case .grid:
            return horizontalSizeClass == .compact ? 158 : 206
        }
    }

    private var posterHeight: CGFloat {
        posterWidth * 1.5
    }
}

private struct MatchedCardModifier: ViewModifier {
    let itemID: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "poster-\(itemID)", in: namespace)
        } else {
            content
        }
    }
}

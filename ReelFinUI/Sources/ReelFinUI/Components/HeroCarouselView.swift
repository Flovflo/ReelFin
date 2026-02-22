import Shared
import SwiftUI

public struct HeroCarouselView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let items: [MediaItem]
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let onTap: (MediaItem) -> Void

    @State private var currentIndex: Int = 0

    public init(
        items: [MediaItem],
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        onTap: @escaping (MediaItem) -> Void
    ) {
        self.items = items
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                    Button {
                        onTap(item)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            CachedRemoteImage(
                                itemID: item.id,
                                type: .backdrop,
                                width: 1200,
                                quality: 80,
                                apiClient: apiClient,
                                imagePipeline: imagePipeline
                            )
                            .overlay {
                                LinearGradient(
                                    colors: [
                                        Color.clear,
                                        Color.black.opacity(0.1),
                                        Color.black.opacity(0.6),
                                        Color.black.opacity(1.0)
                                    ],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.name)
                                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(2)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 4)

                                if let summary = item.overview, !summary.isEmpty {
                                    Text(summary)
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .lineLimit(3)
                                        .foregroundStyle(.white.opacity(0.82))
                                }

                                HStack(spacing: 10) {
                                    Label("Play", systemImage: "play.fill")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(.white.opacity(0.92))
                                        .foregroundStyle(.black)
                                        .clipShape(Capsule())

                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .padding(10)
                                        .background(.white.opacity(0.22))
                                        .clipShape(Circle())
                                }
                                .padding(.top, 4)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                        .frame(height: heroHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .tag(itemIndex)
                }
            }
            .frame(height: heroHeight)
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom Apple TV Dots
            HStack(spacing: 6) {
                ForEach(0..<items.count, id: \.self) { dotIndex in
                    Circle()
                        .fill(currentIndex == dotIndex ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                        .animation(.snappy(duration: 0.2), value: currentIndex)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var heroHeight: CGFloat {
        // ~60% of screen width in height gives it that massive vertical TV feel without breaking max height constraints
        UIScreen.main.bounds.width * 1.35
    }
}

#if os(iOS) || os(tvOS)
import Shared
import SwiftUI

struct FloatingPreviewDescriptor {
    let badge: String
    let title: String
    let subtitle: String
    let palette: [Color]
    let posterAssetName: String?
    let posterURL: URL?

    init(
        badge: String,
        title: String,
        subtitle: String,
        palette: [Color],
        posterAssetName: String? = nil,
        posterURL: URL? = nil
    ) {
        self.badge = badge
        self.title = title
        self.subtitle = subtitle
        self.palette = palette
        self.posterAssetName = posterAssetName
        self.posterURL = posterURL
    }
}

struct FloatingPreviewCard: View {
    let descriptor: FloatingPreviewDescriptor
    let width: CGFloat
    let highlight: Color
    let imagePipeline: (any ImagePipelineProtocol)?

    init(
        descriptor: FloatingPreviewDescriptor,
        width: CGFloat,
        highlight: Color,
        imagePipeline: (any ImagePipelineProtocol)? = nil
    ) {
        self.descriptor = descriptor
        self.width = width
        self.highlight = highlight
        self.imagePipeline = imagePipeline
    }

    private var isCompactCard: Bool {
        width < 150
    }

    private var hasOverlayCopy: Bool {
        !descriptor.badge.isEmpty || !descriptor.title.isEmpty || !descriptor.subtitle.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cardArtwork
            cardGlass

            LinearGradient(
                colors: [.clear, .black.opacity(hasOverlayCopy ? 0.06 : 0.03), .black.opacity(hasOverlayCopy ? 0.68 : 0.12)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                if !descriptor.badge.isEmpty {
                    Text(descriptor.badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if #available(iOS 26.0, tvOS 26.0, *) {
                                Color.clear
                                    .glassEffect(.regular.tint(Color.white.opacity(0.05)), in: .capsule)
                            } else {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            }
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    if !descriptor.title.isEmpty {
                        Text(descriptor.title)
                            .font(.system(size: isCompactCard ? 21 : 26, weight: .bold))
                            .tracking(-0.4)
                            .foregroundStyle(Color.white.opacity(0.98))
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.34), radius: 10, x: 0, y: 3)
                    }

                    if !descriptor.subtitle.isEmpty {
                        Text(descriptor.subtitle)
                            .font(.system(size: isCompactCard ? 13 : 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 2)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: width)
        .aspectRatio(0.68, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .overlay { specularOverlay }
        .shadow(color: .black.opacity(0.40), radius: 34, x: 0, y: 22)
    }

    private var cardArtwork: some View {
        ZStack {
            fallbackArtwork

            if let posterAssetName = descriptor.posterAssetName {
                RemotePosterArtworkView(resourceName: posterAssetName)
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04),
                                .clear,
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
            } else if let posterURL = descriptor.posterURL, let imagePipeline {
                RemotePosterArtworkView(url: posterURL, imagePipeline: imagePipeline)
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04),
                                .clear,
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
            }
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: descriptor.palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .saturation(1.04)
            .contrast(1.06)

            Circle()
                .fill(highlight.opacity(0.24))
                .frame(width: width * 0.84, height: width * 0.84)
                .blur(radius: width * 0.10)
                .offset(x: width * 0.20, y: -width * 0.30)

            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: width * 0.54, height: width * 1.02)
                .rotationEffect(.degrees(-11))
                .offset(x: -width * 0.10, y: -width * 0.05)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.black.opacity(0.14))
                .frame(width: width * 0.40, height: width * 0.88)
                .rotationEffect(.degrees(9))
                .offset(x: width * 0.16, y: width * 0.04)

            Ellipse()
                .fill(Color.white.opacity(0.10))
                .frame(width: width * 0.84, height: width * 0.18)
                .blur(radius: width * 0.06)
                .offset(y: -width * 0.58)

            Ellipse()
                .fill(Color.white.opacity(0.18))
                .frame(width: width * 0.58, height: width * 0.18)
                .blur(radius: width * 0.06)
                .offset(y: width * 0.52)
        }
    }

    @ViewBuilder
    private var cardGlass: some View {
        if descriptor.posterAssetName != nil || descriptor.posterURL != nil {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.008))
        } else if #available(iOS 26.0, tvOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(Color.white.opacity(0.035)), in: .rect(cornerRadius: 34))
        }
    }

    private var specularOverlay: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        .clear,
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .opacity(0.30)
    }
}
#endif

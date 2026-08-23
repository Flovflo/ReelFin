import Shared
import SwiftUI
import UIKit

struct EditorialMediaIdentityView: View {
    enum Style: Equatable {
        case iosHero
        case tvHero
        case landscapeRail
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.reelFinDisplayDensity) private var displayDensity

    let style: Style
    let item: MediaItem
    let fallbackTitle: String
    let kicker: String?
    let metadata: String?
    let apiClient: any JellyfinAPIClientProtocol
    let imagePipeline: any ImagePipelineProtocol
    let loadsRemoteLogo: Bool

    @State private var logoImage: UIImage?
    @State private var logoItemID: String?

    init(
        style: Style,
        item: MediaItem,
        fallbackTitle: String,
        kicker: String? = nil,
        metadata: String? = nil,
        apiClient: any JellyfinAPIClientProtocol,
        imagePipeline: any ImagePipelineProtocol,
        loadsRemoteLogo: Bool = true
    ) {
        self.style = style
        self.item = item
        self.fallbackTitle = fallbackTitle
        self.kicker = kicker
        self.metadata = metadata
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.loadsRemoteLogo = loadsRemoteLogo
    }

    var body: some View {
        VStack(alignment: stackAlignment, spacing: stackSpacing) {
            if let kicker = normalized(kicker) {
                Text(kicker.uppercased())
                    .font(.system(size: kickerFontSize, weight: .bold, design: .rounded))
                    .tracking(kickerTracking)
                    .foregroundStyle(ReelFinTheme.editorialAccent)
                    .lineLimit(1)
            }

            identity

            if let metadata = normalized(metadata) {
                Text(metadata)
                    .font(.system(size: metadataFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReelFinTheme.editorialSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: identityMaxWidth, alignment: contentAlignment)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            EditorialMediaIdentityAccessibility.label(
                itemName: fallbackTitle,
                kicker: kicker,
                metadata: metadata
            )
        )
        .accessibilityIdentifier(
            EditorialMediaIdentityAccessibility.identifier(itemID: item.id)
        )
        .accessibilityAddTraits(.isHeader)
        .task(id: logoLoadTaskID) {
            guard loadsRemoteLogo else {
                logoImage = nil
                logoItemID = nil
                return
            }
            await loadLogo(for: logoRequest)
        }
    }

    private var identity: some View {
        ZStack(alignment: contentAlignment) {
            fallbackTitleView
                .opacity(visibleLogo == nil ? 1 : 0)

            if let visibleLogo {
                Image(uiImage: visibleLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: identityMaxWidth,
                        maxHeight: identityHeight,
                        alignment: contentAlignment
                    )
                    .shadow(
                        color: .black.opacity(logoShadowOpacity),
                        radius: logoShadowRadius,
                        x: 0,
                        y: logoShadowYOffset
                    )
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .frame(
            maxWidth: identityMaxWidth,
            minHeight: identityHeight,
            maxHeight: identityHeight,
            alignment: contentAlignment
        )
        .animation(
            .easeInOut(duration: EditorialMotion.heroPageDuration(reduceMotion: reduceMotion)),
            value: visibleLogo != nil
        )
    }

    private var fallbackTitleView: some View {
        Text(displayedFallbackTitle)
            .font(.system(size: fallbackFontSize, weight: fallbackFontWeight, design: .rounded))
            .tracking(fallbackTracking)
            .foregroundStyle(ReelFinTheme.editorialPrimaryText)
            .multilineTextAlignment(textAlignment)
            .lineLimit(titleLineLimit)
            .minimumScaleFactor(minimumTitleScale)
            .allowsTightening(true)
            .frame(maxWidth: identityMaxWidth, alignment: contentAlignment)
            .shadow(
                color: .black.opacity(titleShadowOpacity),
                radius: titleShadowRadius,
                x: 0,
                y: titleShadowYOffset
            )
    }

    private var visibleLogo: UIImage? {
        logoItemID == item.id ? logoImage : nil
    }

    private var displayedFallbackTitle: String {
        style == .iosHero ? fallbackTitle : fallbackTitle.uppercased()
    }

    private var logoRequest: ArtworkRequest {
        ArtworkRequest.make(for: item, role: .logo)
    }

    private var logoLoadTaskID: String {
        "\(item.id)-\(loadsRemoteLogo)"
    }

    private func loadLogo(for request: ArtworkRequest) async {
        guard !Task.isCancelled else { return }
        logoImage = nil
        logoItemID = nil

        let resolvedURL = await apiClient.imageURL(for: request)
        guard !Task.isCancelled, let url = resolvedURL else { return }

        if let cached = await imagePipeline.cachedImage(for: url) {
            guard !Task.isCancelled else { return }
            guard let readable = try? await LogoCropScheduler.shared.crop(cached) else { return }
            guard !Task.isCancelled else { return }
            publish(readable, for: request.itemID)
            return
        }
        guard !Task.isCancelled else { return }

        if url.scheme == "mock-image" {
            guard let readable = try? await LogoCropScheduler.shared.crop(mockLogoImage()) else { return }
            guard !Task.isCancelled else { return }
            publish(readable, for: request.itemID)
            return
        }

        let consumerID = ImageRequestConsumerID()
        do {
            let downloaded = try await withTaskCancellationHandler {
                try await imagePipeline.image(for: url, consumer: consumerID)
            } onCancel: {
                imagePipeline.cancel(url: url, consumer: consumerID)
            }
            imagePipeline.cancel(url: url, consumer: consumerID)
            guard !Task.isCancelled else { return }
            guard let readable = try? await LogoCropScheduler.shared.crop(downloaded) else { return }
            guard !Task.isCancelled else { return }
            publish(readable, for: request.itemID)
        } catch {
            imagePipeline.cancel(url: url, consumer: consumerID)
        }
    }

    private func publish(_ image: UIImage?, for itemID: String) {
        guard !Task.isCancelled else { return }
        logoImage = image
        logoItemID = image == nil ? nil : itemID
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var stackAlignment: HorizontalAlignment {
        style == .iosHero ? .center : .leading
    }

    private var contentAlignment: Alignment {
        style == .iosHero ? .center : .leading
    }

    private var textAlignment: TextAlignment {
        style == .iosHero ? .center : .leading
    }

    private var stackSpacing: CGFloat {
        switch style {
        case .iosHero: return 10
        case .tvHero: return 12
        case .landscapeRail: return 6
        }
    }

    private var identityMaxWidth: CGFloat {
        switch style {
        case .iosHero:
            return horizontalSizeClass == .compact ? 340 : 520
        case .tvHero:
            return 540
        case .landscapeRail:
            return displayDensity.scaledVisualSize(horizontalSizeClass == .compact ? 190 : 250)
        }
    }

    private var identityHeight: CGFloat {
        switch style {
        case .iosHero:
            return dynamicTypeSize.isAccessibilitySize ? 124 : 108
        case .tvHero:
            return 120
        case .landscapeRail:
            return displayDensity.scaledVisualSize(horizontalSizeClass == .compact ? 44 : 58)
        }
    }

    private var fallbackFontSize: CGFloat {
        switch style {
        case .iosHero:
            return dynamicTypeSize.isAccessibilitySize ? 34 : 30
        case .tvHero:
            return 68
        case .landscapeRail:
            return displayDensity.scaledTextSize(horizontalSizeClass == .compact ? 22 : 28)
        }
    }

    private var minimumTitleScale: CGFloat {
        switch style {
        case .iosHero: return 0.72
        case .tvHero: return 0.55
        case .landscapeRail: return 0.78
        }
    }

    private var fallbackTracking: CGFloat {
        if style == .iosHero {
            return fallbackTitle.count <= 8 ? 1.2 : 0.2
        }
        return fallbackTitle.count <= 8 ? (style == .tvHero ? 6 : 4) : 1.4
    }

    private var fallbackFontWeight: Font.Weight {
        style == .iosHero ? .bold : .black
    }

    private var titleLineLimit: Int {
        style == .iosHero ? 3 : 2
    }

    private var kickerFontSize: CGFloat {
        switch style {
        case .iosHero: return 12
        case .tvHero: return 18
        case .landscapeRail: return 11
        }
    }

    private var kickerTracking: CGFloat {
        style == .tvHero ? 1.8 : 1.4
    }

    private var metadataFontSize: CGFloat {
        switch style {
        case .iosHero: return 15
        case .tvHero: return 22
        case .landscapeRail: return 13
        }
    }

    private var logoShadowOpacity: Double {
        style == .landscapeRail ? 0.30 : 0.58
    }

    private var logoShadowRadius: CGFloat {
        style == .landscapeRail ? 8 : 12
    }

    private var logoShadowYOffset: CGFloat {
        style == .landscapeRail ? 4 : 5
    }

    private var titleShadowOpacity: Double {
        style == .landscapeRail ? 0.28 : 0.56
    }

    private var titleShadowRadius: CGFloat {
        style == .landscapeRail ? 6 : 14
    }

    private var titleShadowYOffset: CGFloat {
        style == .landscapeRail ? 3 : 6
    }

    private func mockLogoImage() -> UIImage {
        let size = CGSize(
            width: max(identityMaxWidth * 2.6, 260),
            height: max(identityHeight * 2.2, 100)
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            let text = fallbackTitle.uppercased() as NSString
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = style == .iosHero ? .center : .left
            paragraph.lineBreakMode = .byTruncatingTail
            text.draw(
                in: CGRect(origin: .zero, size: size),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: fallbackFontSize * 1.4, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                    .kern: fallbackTracking
                ]
            )
        }
    }
}

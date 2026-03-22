import Combine
import Shared
import SwiftUI

public struct HeroCarouselView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    private let items: [MediaItem]
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let onTap: (MediaItem) -> Void
    private let onPlay: ((MediaItem) -> Void)?
    private let onVisibleItemChange: ((MediaItem) -> Void)?

    @State private var currentIndex = 0
    private let timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    public init(
        items: [MediaItem],
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        onVisibleItemChange: ((MediaItem) -> Void)? = nil,
        onPlay: ((MediaItem) -> Void)? = nil,
        onTap: @escaping (MediaItem) -> Void
    ) {
        self.items = items
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.onVisibleItemChange = onVisibleItemChange
        self.onPlay = onPlay
        self.onTap = onTap
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            #if os(tvOS)
            tvBody
            #else
            iosBody
            #endif
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - iOS Body (unchanged)
    // ──────────────────────────────────────────────

    #if os(iOS)
    private var iosBody: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                TabView(selection: Binding(
                    get: { currentIndex },
                    set: { currentIndex = $0 }
                )) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onTap(item)
                        } label: {
                            iosHeroContent(for: item, size: proxy.size)
                                .frame(width: proxy.size.width, height: heroHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                        .accessibilityLabel(item.name)
                        .accessibilityAddTraits(.isButton)
                        .clipped()
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: proxy.size.width, height: heroHeight)
                .ignoresSafeArea(edges: .top)
                .clipped()

                if items.count > 1 {
                    pageControl
                }
            }
            .frame(width: proxy.size.width, height: heroHeight, alignment: .bottom)
        }
        .frame(height: heroHeight)
        .onReceive(timer) { _ in
            if items.count > 1 {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    currentIndex = (currentIndex + 1) % items.count
                }
            }
        }
        .onAppear {
            if let currentItem = items[safe: currentIndex] ?? items.first {
                onVisibleItemChange?(currentItem)
            }
        }
        .onChange(of: currentIndex) { _, newValue in
            if let currentItem = items[safe: newValue] {
                onVisibleItemChange?(currentItem)
            }
        }
    }

    private func iosHeroContent(for item: MediaItem, size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            Color.black

            backdropImage(for: item, size: size)

            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.45), location: 0.5),
                            .init(color: .black.opacity(0.92), location: 0.78),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .center, spacing: 12) {
                if let badgeText = promoBadge(for: item) {
                    Text(badgeText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassPanelStyle(cornerRadius: 8)
                }

                Text(item.name)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 32 : 44, weight: .heavy, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .accessibilityAddTraits(.isHeader)

                Text(heroMetadataText(for: item))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                heroActionButtons(for: item, immersive: false)
                    .padding(.top, 12)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 60)
            .frame(width: max(size.width - (horizontalPadding * 2), 0), alignment: .center)
        }
        .frame(width: size.width, height: heroHeight)
        .clipped()
    }
    #endif

    // ──────────────────────────────────────────────
    // MARK: - tvOS Body – Cinematic Apple TV style
    // ──────────────────────────────────────────────

    #if os(tvOS)
    private var tvBody: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                // Full-bleed backdrop – crossfade between items
                tvBackdrop(size: proxy.size)

                // Cinematic gradient scrims
                tvGradientOverlay

                // Content layer – bottom-left
                tvContentOverlay(size: proxy.size)

                // Page indicators
                if items.count > 1 {
                    tvPageControl
                        .padding(.bottom, 20)
                }
            }
            .frame(width: proxy.size.width, height: heroHeight)
        }
        .frame(height: heroHeight)
        .ignoresSafeArea(edges: .top)
        .focusSection()
        .onMoveCommand(perform: handleMoveCommand)
        .onReceive(timer) { _ in
            guard items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
        .onAppear {
            if let item = items[safe: currentIndex] ?? items.first {
                onVisibleItemChange?(item)
            }
        }
        .onChange(of: currentIndex) { _, newValue in
            if let item = items[safe: newValue] {
                onVisibleItemChange?(item)
            }
        }
    }

    // MARK: Backdrop

    @ViewBuilder
    private func tvBackdrop(size: CGSize) -> some View {
        let item = items[safe: currentIndex] ?? items[0]
        CachedRemoteImage(
            itemID: item.id,
            type: .backdrop,
            width: backdropImageWidth(for: size),
            quality: 90,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
        .frame(width: size.width, height: heroHeight)
        .clipped()
        .id(item.id) // triggers crossfade
        .transition(.opacity.animation(.easeInOut(duration: 0.6)))
        .animation(.easeInOut(duration: 0.6), value: currentIndex)
    }

    // MARK: Gradient Overlay

    private var tvGradientOverlay: some View {
        ZStack {
            // Left reading gradient – soft, cinematic
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.88), location: 0),
                    .init(color: .black.opacity(0.65), location: 0.25),
                    .init(color: .black.opacity(0.25), location: 0.50),
                    .init(color: .clear, location: 0.70),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Bottom fade to black – blends into content rows
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.30), location: 0.65),
                    .init(color: .black.opacity(0.85), location: 0.85),
                    .init(color: .black, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle top vignette for status/tab area
            LinearGradient(
                colors: [.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: Content Overlay

    @ViewBuilder
    private func tvContentOverlay(size: CGSize) -> some View {
        let item = items[safe: currentIndex] ?? items[0]

        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                // Promo badge (glass capsule)
                if let badge = promoBadge(for: item) {
                    Text(badge)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                // Title – try logo image, fall back to large text
                TVHeroTitleView(
                    item: item,
                    apiClient: apiClient,
                    imagePipeline: imagePipeline
                )

                // Genre · Rating line
                tvGenreRatingRow(for: item)

                // Overview
                if let overview = trimmedOverview(for: item) {
                    Text(overview)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(3)
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.top, 2)
                }

                // Year · Runtime · Quality badges
                tvMetadataRow(for: item)
                    .padding(.top, 2)

                // Action buttons – individually focusable
                tvActionButtons(for: item)
                    .padding(.top, 8)
            }
            .padding(.leading, 80)
            .padding(.bottom, 72)
            .frame(maxWidth: size.width * 0.52, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(.easeInOut(duration: 0.5), value: currentIndex)
    }

    // MARK: Genre · Rating Row

    @ViewBuilder
    private func tvGenreRatingRow(for item: MediaItem) -> some View {
        HStack(spacing: 10) {
            Text(mediaTypeLabel(for: item))
                .foregroundStyle(.white.opacity(0.85))

            if !item.genres.isEmpty {
                Text("·")
                    .foregroundStyle(.white.opacity(0.45))
                Text(item.genres.prefix(2).joined(separator: " · "))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let rating = item.communityRating {
                Text("·")
                    .foregroundStyle(.white.opacity(0.45))
                // Age/community rating in bordered capsule
                Text(String(format: "%.1f", rating))
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(.white.opacity(0.4), lineWidth: 1)
                    )
            }
        }
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: Metadata Row (Year · Runtime · Quality)

    @ViewBuilder
    private func tvMetadataRow(for item: MediaItem) -> some View {
        HStack(spacing: 10) {
            if let year = item.year {
                Text(String(year))
            }

            if let runtime = item.runtimeDisplayText {
                Text("·")
                    .foregroundStyle(.white.opacity(0.4))
                Text(runtime)
            }

            // Quality badges – glass capsules
            ForEach(featureBadges(for: item), id: \.self) { badge in
                tvQualityBadge(badge)
            }
        }
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
    }

    private func tvQualityBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: Action Buttons

    @ViewBuilder
    private func tvActionButtons(for item: MediaItem) -> some View {
        TVHeroCapsuleButton(
            title: primaryActionTitle(for: item),
            systemImage: "play.fill",
            onMoveCommand: handleMoveCommand,
            action: { (onPlay ?? onTap)(item) }
        )
    }

    // MARK: Page Control

    private var tvPageControl: some View {
        HStack(spacing: 8) {
            ForEach(0..<items.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? .white : .white.opacity(0.35))
                    .frame(width: index == currentIndex ? 10 : 7, height: index == currentIndex ? 10 : 7)
                    .animation(.easeInOut(duration: 0.25), value: currentIndex)
            }
        }
    }

    // MARK: Paging

    private func pageForward() {
        guard items.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            currentIndex = (currentIndex + 1) % items.count
        }
    }

    private func pageBackward() {
        guard items.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            currentIndex = (currentIndex - 1 + items.count) % items.count
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            pageBackward()
        case .right:
            pageForward()
        default:
            break
        }
    }
    #endif

    // ──────────────────────────────────────────────
    // MARK: - Shared helpers
    // ──────────────────────────────────────────────

    private func backdropImage(for item: MediaItem, size: CGSize) -> some View {
        CachedRemoteImage(
            itemID: item.id,
            type: .backdrop,
            width: backdropImageWidth(for: size),
            quality: 85,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
        .frame(width: size.width, height: heroHeight)
        .clipped()
    }

    private var pageControl: some View {
        HStack(spacing: 6) {
            ForEach(0..<items.count, id: \.self) { dotIndex in
                Capsule()
                    .fill(currentIndex == dotIndex ? Color.white : Color.white.opacity(0.34))
                    .frame(width: currentIndex == dotIndex ? 24 : 8, height: 8)
                    .animation(.snappy(duration: 0.2), value: currentIndex)
            }
        }
        .padding(.bottom, pageControlBottomPadding)
    }

    #if os(iOS)
    @ViewBuilder
    private func heroActionButtons(for item: MediaItem, immersive: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                onTap(item)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text(primaryActionTitle(for: item))
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .foregroundStyle(.black)
                .background(Color.white, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: currentIndex)

            heroCircleButton(symbol: "plus") {
                onTap(item)
            }
        }
    }

    private func heroCircleButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 62, height: 62)
                .foregroundStyle(.white)
                .background(Color.white.opacity(0.12), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
    #endif

    // ──────────────────────────────────────────────
    // MARK: - Metadata helpers
    // ──────────────────────────────────────────────

    private func promoBadge(for item: MediaItem) -> String? {
        if item.mediaType == .episode {
            if let s = item.parentIndexNumber, let e = item.indexNumber {
                return "S\(s), E\(e)"
            }
            return "New Episode"
        }
        if item.mediaType == .series {
            return "TV Series"
        }
        return nil
    }

    private func mediaTypeLabel(for item: MediaItem) -> String {
        switch item.mediaType {
        case .series: return "TV Show"
        case .movie: return "Movie"
        case .episode: return "Episode"
        default: return "Media"
        }
    }

    private func featureBadges(for item: MediaItem) -> [String] {
        var badges: [String] = []
        if item.has4K { badges.append("4K") }
        if item.hasDolbyVision { badges.append("Dolby Vision") }
        if item.hasClosedCaptions { badges.append("CC") }
        return badges
    }

    private func primaryActionTitle(for item: MediaItem) -> String {
        if item.mediaType == .episode,
           let s = item.parentIndexNumber, let e = item.indexNumber {
            return "Resume S\(s), E\(e)"
        }
        if item.playbackProgress ?? 0 > 0 {
            return "Resume"
        }
        return item.mediaType == .series ? "Play" : "Play"
    }

    private func trimmedOverview(for item: MediaItem) -> String? {
        guard let overview = item.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !overview.isEmpty else { return nil }
        return overview
    }

    private func heroMetadataText(for item: MediaItem) -> String {
        var entries: [String] = []
        entries.append(mediaTypeLabel(for: item))
        if !item.genres.isEmpty {
            entries.append(item.genres.prefix(2).joined(separator: " • "))
        }
        return entries.joined(separator: " • ")
    }

    private func remainingTimeText(for item: MediaItem) -> String? {
        guard let progress = item.playbackProgress, progress > 0,
              let runtimeMinutes = item.runtimeMinutes else { return nil }
        let remaining = Int(Double(runtimeMinutes) * (1 - progress))
        guard remaining > 0 else { return nil }
        if remaining >= 60 { return "\(remaining / 60)h \(remaining % 60)m" }
        return "\(remaining)m"
    }

    // ──────────────────────────────────────────────
    // MARK: - Layout constants
    // ──────────────────────────────────────────────

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 32 : 48
    }

    private var heroHeight: CGFloat {
        #if os(tvOS)
        return 880
        #else
        if horizontalSizeClass == .compact {
            return dynamicTypeSize.isAccessibilitySize ? 620 : 540
        }
        return dynamicTypeSize.isAccessibilitySize ? 720 : 660
        #endif
    }

    private var pageControlBottomPadding: CGFloat {
        #if os(tvOS)
        return 28
        #else
        return 24
        #endif
    }

    private func backdropImageWidth(for size: CGSize) -> Int {
        let requestedWidth = Int((size.width * displayScale).rounded(.up))
        return min(max(requestedWidth, 720), 2200)
    }
}

#if os(tvOS)
private struct TVHeroCapsuleButton: View {
    @Environment(\.tvTopNavigationFocusAction) private var requestTopNavigationFocus
    @FocusState private var isFocused: Bool

    let title: String
    let systemImage: String
    let onMoveCommand: (MoveCommandDirection) -> Void
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .font(.system(size: 22, weight: .semibold, design: .rounded))
        .foregroundStyle(isFocused ? Color.black.opacity(0.92) : .white)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(backgroundFill, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.22 : 0.12), lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .scaleEffect(isFocused ? 1.04 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.34 : 0.16), radius: isFocused ? 22 : 10, x: 0, y: isFocused ? 12 : 6)
        .focusable(true, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onMoveCommand(perform: handleMoveCommand)
        .onTapGesture(perform: action)
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isFocused)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Swipe left or right to browse featured titles.")
    }

    private var backgroundFill: Color {
        isFocused ? .white : Color.white.opacity(0.10)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            requestTopNavigationFocus?(.watchNow)
        case .left, .right:
            onMoveCommand(direction)
        default:
            break
        }
    }
}
#endif

// ──────────────────────────────────────────────
// MARK: - tvOS Hero Title (Logo image → text fallback)
// ──────────────────────────────────────────────

#if os(tvOS)
/// Attempts to load a transparent logo image from Jellyfin.
/// Falls back to a large bold text title if unavailable.
private struct TVHeroTitleView: View {
    let item: MediaItem
    let apiClient: JellyfinAPIClientProtocol
    let imagePipeline: ImagePipelineProtocol

    @State private var logoImage: UIImage?
    @State private var logoFailed = false

    var body: some View {
        Group {
            if let logo = logoImage {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 540, maxHeight: 120, alignment: .leading)
                    .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 4)
                    .transition(.opacity)
            } else {
                Text(item.name)
                    .font(.system(size: 68, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 6)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .task(id: item.id) {
            await loadLogo()
        }
    }

    private func loadLogo() async {
        logoImage = nil
        logoFailed = false

        guard let url = await apiClient.imageURL(
            for: item.id, type: .logo, width: 800, quality: 90
        ) else {
            logoFailed = true
            return
        }

        // Try cache first
        if let cached = await imagePipeline.cachedImage(for: url) {
            withAnimation(.easeIn(duration: 0.3)) { logoImage = cached }
            return
        }

        do {
            let downloaded = try await imagePipeline.image(for: url)
            withAnimation(.easeIn(duration: 0.3)) { logoImage = downloaded }
        } catch {
            logoFailed = true
        }
    }
}
#endif

// ──────────────────────────────────────────────
// MARK: - Utilities
// ──────────────────────────────────────────────

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

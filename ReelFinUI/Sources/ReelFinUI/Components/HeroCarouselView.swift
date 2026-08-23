import Shared
import SwiftUI
#if os(iOS)
import Combine
#endif

public struct HeroCarouselView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [MediaItem]
    private let apiClient: JellyfinAPIClientProtocol
    private let imagePipeline: ImagePipelineProtocol
    private let onTap: (MediaItem) -> Void
    private let onPlay: ((MediaItem) -> Void)?
    private let onToggleWatchlist: ((MediaItem) -> Void)?
    private let onVisibleItemChange: ((MediaItem) -> Void)?
    private let selectedItemID: Binding<String?>?
    private let transitionNamespace: Namespace.ID?
    private let transitionSourceID: ((MediaItem) -> String?)?
    private let usesTVInlineDetailTransition: Bool
    private let tvFocusedItemID: FocusState<String?>.Binding?
    private let tvPrimaryActionFocusID: String?

    @State private var currentIndex = 0
    #if os(iOS)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase

    @GestureState private var isUserInteracting = false
    @State private var directPageHapticTrigger = 0
    @State private var lowResolutionHeroIDs = Set<String>()
    private let timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    #endif

    public init(
        items: [MediaItem],
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol,
        selectedItemID: Binding<String?>? = nil,
        transitionNamespace: Namespace.ID? = nil,
        transitionSourceID: ((MediaItem) -> String?)? = nil,
        usesTVInlineDetailTransition: Bool = false,
        tvFocusedItemID: FocusState<String?>.Binding? = nil,
        tvPrimaryActionFocusID: String? = nil,
        onVisibleItemChange: ((MediaItem) -> Void)? = nil,
        onPlay: ((MediaItem) -> Void)? = nil,
        onToggleWatchlist: ((MediaItem) -> Void)? = nil,
        onTap: @escaping (MediaItem) -> Void
    ) {
        self.items = items
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline
        self.selectedItemID = selectedItemID
        self.transitionNamespace = transitionNamespace
        self.transitionSourceID = transitionSourceID
        self.usesTVInlineDetailTransition = usesTVInlineDetailTransition
        self.tvFocusedItemID = tvFocusedItemID
        self.tvPrimaryActionFocusID = tvPrimaryActionFocusID
        self.onVisibleItemChange = onVisibleItemChange
        self.onPlay = onPlay
        self.onToggleWatchlist = onToggleWatchlist
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
                    set: { selectPageDirectly($0) }
                )) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        iosHeroCard(for: item, index: index, size: proxy.size)
                            .tag(index)
                            .clipped()
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: proxy.size.width, height: heroHeight)
                .ignoresSafeArea(edges: .top)
                .clipped()
                .simultaneousGesture(heroInteractionGesture)

                if items.count > 1 {
                    pageControl
                }
            }
            .frame(width: proxy.size.width, height: heroHeight, alignment: .bottom)
        }
        .frame(height: heroHeight)
        .onReceive(timer) { _ in
            advanceAutomaticallyIfAllowed()
        }
        .sensoryFeedback(.selection, trigger: directPageHapticTrigger)
        .onAppear {
            syncSelectionFromBinding()
            if let currentItem = items[safe: currentIndex] ?? items.first {
                selectedItemID?.wrappedValue = currentItem.id
                onVisibleItemChange?(currentItem)
            }
        }
        .onChange(of: currentIndex) { _, newValue in
            if let currentItem = items[safe: newValue] {
                selectedItemID?.wrappedValue = currentItem.id
                onVisibleItemChange?(currentItem)
            }
        }
        .onChange(of: selectedItemValue) { _, _ in
            syncSelectionFromBinding()
        }
        .onChange(of: itemIDs) { _, _ in
            reconcileItems()
        }
    }

    private func iosHeroCard(for item: MediaItem, index: Int, size: CGSize) -> some View {
        let artworkLayers = HeroArtworkLoadingPolicy.layers(
            pageIndex: index,
            currentIndex: currentIndex,
            lowResolutionReady: lowResolutionHeroIDs.contains(item.id)
        )

        return ZStack(alignment: .bottom) {
            Button {
                onTap(item)
            } label: {
                iosHeroBackdrop(for: item, size: size, artworkLayers: artworkLayers)
                    .frame(width: proxySafeWidth(size.width), height: heroHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(.isButton)

            iosHeroContentOverlay(for: item, size: size, artworkLayers: artworkLayers)
        }
        .frame(width: size.width, height: heroHeight)
        .clipped()
    }

    private func iosHeroBackdrop(
        for item: MediaItem,
        size: CGSize,
        artworkLayers: [HeroArtworkLoadingLayer]
    ) -> some View {
        ZStack(alignment: .bottom) {
            Color.black

            backdropImage(for: item, size: size, artworkLayers: artworkLayers)
                .scaleEffect(1.035)
                // Keep central faces out from under the Dynamic Island while preserving the
                // full-bleed editorial treatment. The black canvas above reads as native chrome.
                .offset(y: 44)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.46), location: 0),
                    .init(color: .clear, location: 0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

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
        }
    }

    private func iosHeroContentOverlay(
        for item: MediaItem,
        size: CGSize,
        artworkLayers: [HeroArtworkLoadingLayer]
    ) -> some View {
        VStack(alignment: .center, spacing: 14) {
            EditorialMediaIdentityView(
                style: .iosHero,
                item: item,
                fallbackTitle: item.name,
                kicker: "Featured",
                metadata: heroMetadataText(for: item),
                apiClient: apiClient,
                imagePipeline: imagePipeline,
                loadsRemoteLogo: artworkLayers.contains(.logo)
            )
            .allowsHitTesting(false)

            heroActionButtons(for: item, immersive: false)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 44)
        .frame(width: max(size.width - (horizontalPadding * 2), 0), alignment: .center)
    }

    private var heroInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isUserInteracting) { _, isInteracting, _ in
                isInteracting = true
            }
    }

    private func selectPageDirectly(_ newIndex: Int) {
        guard newIndex != currentIndex else { return }
        currentIndex = newIndex
        if HeroRotationPolicy.allowsHaptic(for: .direct) {
            directPageHapticTrigger &+= 1
        }
    }

    private func advanceAutomaticallyIfAllowed() {
        guard HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: scenePhase == .active,
            isUserInteracting: isUserInteracting,
            reduceMotion: reduceMotion,
            voiceOverEnabled: voiceOverEnabled,
            itemCount: items.count
        ) else {
            return
        }
        guard let nextIndex = HeroRotationPolicy.nextIndex(
            currentIndex: currentIndex,
            itemCount: items.count
        ) else {
            return
        }

        withAnimation(.easeInOut(duration: EditorialMotion.heroPageDuration(reduceMotion: reduceMotion))) {
            currentIndex = nextIndex
        }
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
        .onAppear {
            syncSelectionFromBinding()
            if let item = items[safe: currentIndex] ?? items.first {
                selectedItemID?.wrappedValue = item.id
                onVisibleItemChange?(item)
            }
        }
        .onChange(of: currentIndex) { _, newValue in
            if let item = items[safe: newValue] {
                selectedItemID?.wrappedValue = item.id
                onVisibleItemChange?(item)
            }
        }
        .onChange(of: selectedItemValue) { _, _ in
            syncSelectionFromBinding()
        }
        .onChange(of: itemIDs) { _, _ in
            reconcileItems()
        }
    }

    // MARK: Backdrop

    @ViewBuilder
    private func tvBackdrop(size: CGSize) -> some View {
        let item = items[safe: currentIndex] ?? items[0]
        CachedRemoteImage(
            request: ArtworkRequest.make(for: item, role: .heroHigh),
            contentMode: .fill,
            apiClient: apiClient,
            imagePipeline: imagePipeline
        )
        .frame(width: size.width, height: heroHeight)
        .clipped()
        .id(item.id) // triggers crossfade
        .transition(.opacity.animation(TVMotion.contentFadeAnimation))
        .modifier(MatchedCardModifier(itemID: transitionID(for: item), namespace: transitionNamespace))
        .modifier(TVHeroInlineDetailSourceModifier(
            itemID: transitionID(for: item),
            namespace: transitionNamespace,
            isEnabled: usesTVInlineDetailTransition
        ))
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
                // Promo badge (static tonal capsule)
                if let badge = promoBadge(for: item) {
                    Text(badge)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(promoBadgeBackground)
                }

                // Shared logo-first identity with an immediate text fallback.
                EditorialMediaIdentityView(
                    style: .tvHero,
                    item: item,
                    fallbackTitle: item.name,
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

            // Quality badges – static tonal capsules
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
            .background(qualityBadgeBackground)
    }

    @ViewBuilder
    private var promoBadgeBackground: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.36))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var qualityBadgeBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.black.opacity(0.34))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    // MARK: Action Buttons

    @ViewBuilder
    private func tvActionButtons(for item: MediaItem) -> some View {
        GlassEffectContainer(spacing: 12) {
            TVHeroCapsuleButton(
                title: primaryActionTitle(for: item),
                systemImage: "play.fill",
                focusedItemID: tvFocusedItemID,
                focusID: tvPrimaryActionFocusID,
                onMoveCommand: handleMoveCommand,
                action: { (onPlay ?? onTap)(item) }
            )
        }
    }

    // MARK: Page Control

    private var tvPageControl: some View {
        HStack(spacing: 8) {
            ForEach(0..<items.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? .white : .white.opacity(0.35))
                    .frame(width: index == currentIndex ? 10 : 7, height: index == currentIndex ? 10 : 7)
            }
        }
    }

    // MARK: Paging

    private func pageForward() {
        guard items.count > 1 else { return }
        withAnimation(TVMotion.heroPageAnimation) {
            currentIndex = (currentIndex + 1) % items.count
        }
    }

    private func pageBackward() {
        guard items.count > 1 else { return }
        withAnimation(TVMotion.heroPageAnimation) {
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

    private var selectedItemValue: String? {
        selectedItemID?.wrappedValue
    }

    private var itemIDs: [String] {
        items.map(\.id)
    }

    private func syncSelectionFromBinding() {
        guard
            let selectedItemValue,
            let newIndex = items.firstIndex(where: { $0.id == selectedItemValue }),
            newIndex != currentIndex
        else {
            return
        }
        currentIndex = newIndex
    }

    private func reconcileItems() {
        guard !items.isEmpty else {
            currentIndex = 0
            selectedItemID?.wrappedValue = nil
            return
        }

        if let selectedItemValue,
           let selectedIndex = items.firstIndex(where: { $0.id == selectedItemValue }) {
            currentIndex = selectedIndex
            return
        }

        currentIndex = min(max(currentIndex, 0), items.count - 1)
        let item = items[currentIndex]
        selectedItemID?.wrappedValue = item.id
        onVisibleItemChange?(item)
    }

    private func transitionID(for item: MediaItem) -> String {
        transitionSourceID?(item) ?? item.id
    }

    // ──────────────────────────────────────────────
    // MARK: - Shared helpers
    // ──────────────────────────────────────────────

    #if os(iOS)
    @ViewBuilder
    private func backdropImage(
        for item: MediaItem,
        size: CGSize,
        artworkLayers: [HeroArtworkLoadingLayer]
    ) -> some View {
        Group {
            if artworkLayers.contains(.lowResolution) {
                ZStack {
                    CachedRemoteImage(
                        request: ArtworkRequest.make(for: item, role: .heroLow),
                        contentMode: .fill,
                        apiClient: apiClient,
                        imagePipeline: imagePipeline,
                        onImageLoaded: {
                            lowResolutionHeroIDs.insert(item.id)
                        }
                    )

                    if artworkLayers.contains(.highResolution) {
                        CachedRemoteImage(
                            request: ArtworkRequest.make(for: item, role: .heroHigh),
                            contentMode: .fill,
                            apiClient: apiClient,
                            imagePipeline: imagePipeline,
                            showsPlaceholder: false
                        )
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: heroHeight)
        .clipped()
        .modifier(MatchedCardModifier(itemID: transitionID(for: item), namespace: transitionNamespace))
    }
    #endif

    private var pageControl: some View {
        HStack(spacing: 6) {
            ForEach(0..<items.count, id: \.self) { dotIndex in
                Capsule()
                    .fill(
                        currentIndex == dotIndex
                            ? ReelFinTheme.editorialAccent
                            : Color.white.opacity(0.34)
                    )
                    .frame(
                        width: currentIndex == dotIndex
                            ? HomeEditorialPresentationPolicy.activeIndicatorWidth
                            : HomeEditorialPresentationPolicy.inactiveIndicatorWidth,
                        height: 8
                    )
                    .animation(
                        .easeInOut(duration: EditorialMotion.heroPageDuration(reduceMotion: reduceMotion)),
                        value: currentIndex
                    )
            }
        }
        .padding(.bottom, pageControlBottomPadding)
    }

    #if os(iOS)
    @ViewBuilder
    private func heroActionButtons(for item: MediaItem, immersive: Bool) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    (onPlay ?? onTap)(item)
                } label: {
                    heroPlaySurface {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                            Text(primaryActionTitle(for: item))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .padding(.horizontal, horizontalSizeClass == .compact ? 18 : 26)
                        .frame(minHeight: 52)
                        .layoutPriority(1)
                        .foregroundStyle(
                            reduceTransparency
                                ? Color.black
                                : ReelFinTheme.editorialPrimaryText
                        )
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(EditorialHeroPressStyle())
                .accessibilityIdentifier("home_featured_play_button_\(item.id)")

                if let onToggleWatchlist {
                    heroCircleButton(
                        symbol: item.isFavorite ? "heart.fill" : "heart",
                        accessibilityLabel: item.isFavorite ? "Unlike" : "Like",
                        accessibilityIdentifier: "home_featured_watchlist_button_\(item.id)",
                        accessibilityValue: item.isFavorite ? "liked" : "not_liked",
                        isActive: item.isFavorite
                    ) {
                        onToggleWatchlist(item)
                    }
                }

                heroCircleButton(
                    symbol: "ellipsis",
                    accessibilityLabel: "More",
                    accessibilityIdentifier: "home_featured_more_button_\(item.id)",
                    accessibilityValue: "",
                    isActive: false
                ) {
                    onTap(item)
                }
            }
        }
    }

    private func heroCircleButton(
        symbol: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        accessibilityValue: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            heroCircleSurface(isActive: isActive) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .foregroundStyle(ReelFinTheme.editorialPrimaryText)
            }
            .contentShape(Circle())
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(EditorialHeroPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private func heroPlaySurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if reduceTransparency {
            content()
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.96))
                }
        } else {
            content()
                .glassEffect(
                    Glass.regular.tint(ReelFinTheme.editorialGlassTint).interactive(),
                    in: .capsule
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func heroCircleSurface<Content: View>(
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if reduceTransparency {
            content()
                .background {
                    Circle().fill(ReelFinTheme.editorialOpaqueFallback)
                }
                .overlay {
                    Circle().stroke(Color.white.opacity(isActive ? 0.24 : 0.14), lineWidth: 1)
                }
        } else {
            content()
                .glassEffect(
                    Glass.regular
                        .tint(isActive ? ReelFinTheme.editorialAccent.opacity(0.16) : ReelFinTheme.editorialGlassTint)
                        .interactive(),
                    in: .circle
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(isActive ? 0.22 : 0.12), lineWidth: 1)
                }
        }
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
        return HomeEditorialPresentationPolicy.iosHeroHeight(
            compact: horizontalSizeClass == .compact,
            accessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        #endif
    }

    private var pageControlBottomPadding: CGFloat {
        #if os(tvOS)
        return 28
        #else
        return 16
        #endif
    }

    private func proxySafeWidth(_ width: CGFloat) -> CGFloat {
        max(width, 0)
    }
}

#if os(iOS)
private struct EditorialHeroPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(
                EditorialMotion.buttonPressAnimation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
#endif

#if os(tvOS)
private struct TVHeroCapsuleButton: View {
    @Environment(\.tvTopNavigationFocusAction) private var requestTopNavigationFocus
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isFocused: Bool

    let title: String
    let systemImage: String
    let focusedItemID: FocusState<String?>.Binding?
    let focusID: String?
    let onMoveCommand: (MoveCommandDirection) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            actionSurface {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .bold))

                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(actionForeground)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .tvMotionFocus(.heroButton, isFocused: isFocused)
        .focused($isFocused)
        .modifier(TVHeroActionFocusModifier(focusedItemID: focusedItemID, focusID: focusID))
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .onMoveCommand(perform: handleMoveCommand)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Swipe left or right to browse featured titles.")
    }

    @ViewBuilder
    private func actionSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        switch EditorialGlassRole.actionCluster.presentation(
            reduceTransparency: reduceTransparency
        ) {
        case .opaque:
            content()
                .background {
                    Capsule(style: .continuous)
                        .fill(ReelFinTheme.editorialOpaqueFallback)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.26 : 0.14), lineWidth: 1)
                }
        case .interactiveGlass:
            content()
                .background {
                    Capsule(style: .continuous)
                        .fill(isFocused ? Color.white.opacity(0.08) : .clear)
                }
                .glassEffect(
                    Glass.regular.tint(
                        isFocused
                            ? ReelFinTheme.editorialAccent.opacity(0.16)
                            : ReelFinTheme.editorialGlassTint
                    )
                        .interactive(),
                    in: .capsule
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.22 : 0.12), lineWidth: 1)
                }
        case .passiveGlass:
            content()
                .glassEffect(
                    Glass.regular.tint(ReelFinTheme.editorialGlassTint),
                    in: .capsule
                )
                .overlay {
                    Capsule(style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
    }

    private var actionForeground: Color {
        if reduceTransparency {
            return ReelFinTheme.editorialPrimaryText
        }
        return isFocused ? Color.black.opacity(0.92) : ReelFinTheme.editorialPrimaryText
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

private struct TVHeroActionFocusModifier: ViewModifier {
    let focusedItemID: FocusState<String?>.Binding?
    let focusID: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focusedItemID, let focusID {
            content.focused(focusedItemID, equals: focusID)
        } else {
            content
        }
    }
}

private struct TVHeroInlineDetailSourceModifier: ViewModifier {
    let itemID: String
    let namespace: Namespace.ID?
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled, let namespace {
            content.matchedGeometryEffect(id: "poster-\(itemID)", in: namespace, isSource: true)
        } else {
            content
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

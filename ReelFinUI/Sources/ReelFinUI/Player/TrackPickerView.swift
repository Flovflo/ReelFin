import Shared
import SwiftUI
import PlaybackEngine

enum PlaybackControlSelection {
    case audio(String)
    case subtitle(String?)
}

enum PlaybackTrackMenuKind: Hashable {
    case audio
    case subtitles
}

struct PlaybackTrackOption: Identifiable, Equatable {
    let trackID: String?
    let title: String
    let badge: String?
    let iconName: String?
    let isSelected: Bool

    var id: String {
        trackID ?? "__none__"
    }

    var accessibilityLabel: String {
        guard let badge, !badge.isEmpty else { return title }
        return "\(title), \(badge)"
    }
}

struct PlaybackControlsModel: Equatable {
    var skipSuggestion: PlaybackSkipSuggestion?
    var audioOptions: [PlaybackTrackOption]
    var subtitleOptions: [PlaybackTrackOption]

    init(
        skipSuggestion: PlaybackSkipSuggestion? = nil,
        audioOptions: [PlaybackTrackOption] = [],
        subtitleOptions: [PlaybackTrackOption] = []
    ) {
        self.skipSuggestion = skipSuggestion
        self.audioOptions = audioOptions
        self.subtitleOptions = subtitleOptions
    }

    var hasSelectableTracks: Bool {
        !audioOptions.isEmpty || !subtitleOptions.isEmpty
    }

    func options(for menu: PlaybackTrackMenuKind) -> [PlaybackTrackOption] {
        switch menu {
        case .audio:
            return audioOptions
        case .subtitles:
            return subtitleOptions
        }
    }

    static func make(
        audioTracks: [MediaTrack],
        subtitleTracks: [MediaTrack],
        selectedAudioID: String?,
        selectedSubtitleID: String?,
        skipSuggestion: PlaybackSkipSuggestion?
    ) -> PlaybackControlsModel {
        let audioOptions: [PlaybackTrackOption]
        if !audioTracks.isEmpty {
            audioOptions = audioTracks.map { track in
                PlaybackTrackOption(
                    trackID: track.id,
                    title: PlaybackTrackPresentation.title(for: track),
                    badge: PlaybackTrackPresentation.audioBadge(for: track),
                    iconName: nil,
                    isSelected: track.id == selectedAudioID
                )
            }
        } else {
            audioOptions = []
        }

        let subtitleOptions: [PlaybackTrackOption]
        if subtitleTracks.isEmpty {
            subtitleOptions = []
        } else {
            subtitleOptions = [
                PlaybackTrackOption(
                    trackID: nil,
                    title: "Off",
                    badge: nil,
                    iconName: "minus.circle",
                    isSelected: selectedSubtitleID == nil
                )
            ] + subtitleTracks.map { track in
                PlaybackTrackOption(
                    trackID: track.id,
                    title: PlaybackTrackPresentation.title(for: track),
                    badge: PlaybackTrackPresentation.subtitleBadge(for: track),
                    iconName: nil,
                    isSelected: track.id == selectedSubtitleID
                )
            }
        }

        return PlaybackControlsModel(
            skipSuggestion: skipSuggestion,
            audioOptions: audioOptions,
            subtitleOptions: subtitleOptions
        )
    }

    static func customAudioOptions(from tracks: [CustomPlaybackAudioTrack]) -> [PlaybackTrackOption] {
        let titleCounts = Dictionary(grouping: tracks, by: \.title).mapValues(\.count)
        var occurrences: [String: Int] = [:]
        return tracks.map { track in
            occurrences[track.title, default: 0] += 1
            let badge = titleCounts[track.title, default: 0] > 1
                ? "Piste \(occurrences[track.title, default: 1])"
                : nil
            return PlaybackTrackOption(
                trackID: track.id,
                title: track.title,
                badge: badge,
                iconName: "waveform",
                isSelected: track.isSelected
            )
        }
    }
}

enum PlaybackTrackPresentation {
    static func title(for track: MediaTrack) -> String {
        if let lang = track.language, !lang.isEmpty {
            let base = String(lang.prefix(2)).lowercased()
            if let localized = Locale.current.localizedString(forLanguageCode: base) {
                return localized.capitalized
            }
        }
        return track.title.isEmpty ? "Piste \(track.index)" : track.title
    }

    static func audioBadge(for track: MediaTrack) -> String? {
        var parts: [String] = []
        if let codec = track.codec {
            parts.append(normalizedAudioCodecLabel(codec))
        }
        if track.isDefault {
            parts.append("Défaut")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func subtitleBadge(for track: MediaTrack) -> String? {
        var parts: [String] = []
        if let codec = track.codec, !codec.isEmpty {
            parts.append(codec.uppercased())
        }
        let lower = track.title.lowercased()
        if track.isForced || lower.contains("forced") || lower.contains("forcé") {
            parts.append("Forcé")
        }
        if track.isDefault {
            parts.append("Défaut")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func normalizedAudioCodecLabel(_ codec: String) -> String {
        switch codec.lowercased() {
        case "eac3", "ec-3", "ec3":
            return "Dolby Digital+"
        case "ac3":
            return "Dolby Digital"
        case "truehd":
            return "TrueHD"
        case "dts":
            return "DTS"
        case "dts-hd", "dtshd", "dtshd-ma", "dtshd_ma":
            return "DTS-HD MA"
        case "aac":
            return "AAC"
        case "flac":
            return "FLAC"
        case "mp3":
            return "MP3"
        case "opus":
            return "Opus"
        default:
            return codec.uppercased()
        }
    }
}

/// Compact, user-facing text for the player popover. Jellyfin and sidecar sources can expose
/// labels such as “VFF Forced - French - Default - SUBRIP”; the popover keeps the original option
/// identity while presenting that metadata as a short title and a secondary detail line.
struct PlaybackTrackMenuOptionPresentation: Equatable {
    let title: String
    let details: String?

    init(option: PlaybackTrackOption) {
        let rawTokens = Self.tokens(in: option.title) + Self.tokens(in: option.badge)
        var language: String?
        var labels: [String] = []
        var metadata: [String] = []

        for rawToken in rawTokens {
            var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            let lowered = token.lowercased()

            if ["off", "disabled", "désactivés", "désactivé"].contains(lowered) {
                language = "Désactivés"
                continue
            }
            if let localizedLanguage = Self.localizedLanguage(lowered) {
                language = localizedLanguage
                continue
            }
            if let codec = Self.codecLabel(lowered) {
                Self.appendUnique(codec, to: &metadata)
                continue
            }

            if lowered.contains("forced") || lowered.contains("forcé") {
                Self.appendUnique("Forcé", to: &metadata)
                token = Self.removing(["Forced", "forced", "Forcé", "forcé"], from: token)
            }
            if lowered.contains("hearing impaired") || lowered.contains("malentendant") || lowered.contains("sdh") {
                Self.appendUnique("Malentendants", to: &metadata)
                token = Self.removing(
                    ["Hearing Impaired", "hearing impaired", "Malentendants", "malentendants", "SDH", "sdh"],
                    from: token
                )
            }

            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedLower = cleaned.lowercased()
            if ["default", "défaut"].contains(cleanedLower) {
                Self.appendUnique("Défaut", to: &metadata)
            } else if !cleaned.isEmpty {
                Self.appendUnique(cleaned, to: &labels)
            }
        }

        if language == "Désactivés" {
            title = "Désactivés"
            details = nil
            return
        }

        let primaryParts = [language].compactMap { $0 } + labels
        title = primaryParts.isEmpty ? option.title : primaryParts.joined(separator: " · ")
        details = metadata.isEmpty ? nil : metadata.joined(separator: " · ")
    }

    private static func tokens(in value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value
            .replacingOccurrences(of: " – ", with: " - ")
            .replacingOccurrences(of: " — ", with: " - ")
            .components(separatedBy: " - ")
            .flatMap { $0.components(separatedBy: " · ") }
    }

    private static func localizedLanguage(_ token: String) -> String? {
        switch token {
        case "french", "français", "francais", "fre", "fra", "fr": return "Français"
        case "english", "anglais", "eng", "en": return "Anglais"
        case "arabic", "arabe", "ara", "ar": return "Arabe"
        case "spanish", "espagnol", "spa", "es": return "Espagnol"
        case "german", "allemand", "deu", "ger", "de": return "Allemand"
        case "italian", "italien", "ita", "it": return "Italien"
        default: return nil
        }
    }

    private static func codecLabel(_ token: String) -> String? {
        switch token {
        case "subrip", "srt": return "SRT"
        case "webvtt", "vtt": return "WebVTT"
        case "ass": return "ASS"
        case "ssa": return "SSA"
        case "pgs", "pgssub": return "PGS"
        case "aac": return "AAC"
        case "ac3": return "Dolby Digital"
        case "eac3", "ec-3", "ec3": return "Dolby Digital+"
        case "truehd": return "TrueHD"
        default: return nil
        }
    }

    private static func removing(_ fragments: [String], from value: String) -> String {
        fragments.reduce(value) { result, fragment in
            result.replacingOccurrences(of: fragment, with: "")
        }
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }
}

struct NativePlayerTrackSelectionMenuView: View {
    let mode: PlaybackTrackMenuKind
    let controls: PlaybackControlsModel
    let onSelect: (PlaybackControlSelection) -> Void
#if os(tvOS)
    @AppStorage(SubtitleBackgroundStyle.defaultsKey)
    private var subtitleStyle: SubtitleBackgroundStyle = .transparent
#else
    @Namespace private var focusNamespace
    @FocusState private var focusedOptionID: String?
#endif

    var body: some View {
#if os(tvOS)
        NativePlayerAVKitMenuView(
            mode: mode,
            controls: controls,
            subtitleStyle: subtitleStyle,
            onSelect: onSelect,
            onSelectStyle: { subtitleStyle = $0 },
            onDismiss: {}
        )
#else
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            Text(primaryTitle)
                .font(.system(size: metrics.titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, metrics.horizontalPadding)

            ScrollView {
                if mode == .audio {
                    audioTrackSection
                } else {
                    subtitlesSection
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: metrics.contentMaxHeight)
        }
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: metrics.panelWidth, alignment: .leading)
        .nativePlayerTrackMenuGlass(cornerRadius: metrics.cornerRadius)
        .nativePlayerTrackMenuFocusScope(focusNamespace)
        .defaultFocus($focusedOptionID, defaultOptionID)
        .background(alignment: .topLeading) {
            if TVLiveUIAutomationPolicy.isEnabledForCurrentProcess {
                ZStack {
                    PlayerAccessibilityMarkerView(identifier: accessibilityIdentifier)
                    PlayerAccessibilityMarkerView(
                        identifier: "native_player_track_focused_title",
                        value: focusedOptionTitle
                    )
                }
                .frame(width: 1, height: 1)
            }
        }
#endif
    }

#if !os(tvOS)
    private var audioTrackSection: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            if controls.audioOptions.isEmpty {
                NativePlayerTrackMenuEmptyRow(title: "Aucune piste audio")
            } else {
                ForEach(controls.audioOptions) { option in
                    NativePlayerTrackMenuRow(option: option, focusedOptionID: $focusedOptionID) {
                        guard let trackID = option.trackID else { return }
                        onSelect(.audio(trackID))
                    }
                    .nativePlayerPrefersDefaultTrackFocus(option.id == defaultOptionID, in: focusNamespace)
                }
            }
        }
    }

    private var subtitlesSection: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            if controls.subtitleOptions.isEmpty {
                NativePlayerTrackMenuEmptyRow(title: "Aucun sous-titre")
            } else {
                ForEach(controls.subtitleOptions) { option in
                    NativePlayerTrackMenuRow(option: option, focusedOptionID: $focusedOptionID) {
                        onSelect(.subtitle(option.trackID))
                    }
                    .nativePlayerPrefersDefaultTrackFocus(option.id == defaultOptionID, in: focusNamespace)
                }
            }
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .audio:
            return "Audio"
        case .subtitles:
            return "Sous-titres"
        }
    }

    private var accessibilityIdentifier: String {
        switch mode {
        case .audio:
            return "native_player_audio_menu"
        case .subtitles:
            return "native_player_subtitles_menu"
        }
    }

    private var metrics: NativePlayerTrackMenuLayout {
        NativePlayerTrackMenuLayout.current
    }

    private var defaultOptionID: String {
        let options = controls.options(for: mode)
        return (options.first(where: \.isSelected) ?? options.first)?.id ?? "__empty__"
    }

    private var focusedOptionTitle: String? {
        guard let focusedOptionID else { return nil }
        return controls.options(for: mode).first(where: { $0.id == focusedOptionID })?.accessibilityLabel
    }
#endif
}

/// A real destination for the tvOS “Vidéo” action. It intentionally reports only user-relevant
/// facts already known by the active route; diagnostics remain in the DEBUG-only panel.
struct NativePlayerVideoInformationView: View {
    var title: String = "Vidéo"
    var accessibilityIdentifier: String = "native_player_video_panel"
    let qualityLabel: String
    let routeLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(title)
                .font(.system(size: metrics.titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            videoRow(title: "Qualité", value: qualityLabel, systemName: "sparkles.tv")
            videoRow(title: "Lecture", value: routeLabel, systemName: "play.rectangle.on.rectangle")
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: metrics.panelWidth, alignment: .leading)
        .nativePlayerTrackMenuGlass(cornerRadius: metrics.cornerRadius)
        .background(alignment: .topLeading) {
            if TVLiveUIAutomationPolicy.isEnabledForCurrentProcess {
                PlayerAccessibilityMarkerView(identifier: accessibilityIdentifier)
                    .frame(width: 1, height: 1)
            }
        }
    }

    private func videoRow(title: String, value: String, systemName: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: systemName)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: metrics.sectionTitleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: metrics.rowTitleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
    }

    private var metrics: NativePlayerTrackMenuLayout { .current }
}

/// Honest Jellyfin metadata for the tvOS Détails action.
/// supplied by Jellyfin; it does not imply people recognition or scene analysis.
struct NativePlayerItemInsightView: View {
    let item: MediaItem?
    let qualityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Détails")
                .font(.system(size: metrics.titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))

            insightRow(title: "Titre", value: item?.name ?? "Contenu en cours")
            if let seriesName = item?.seriesName, !seriesName.isEmpty {
                insightRow(title: "Série", value: seriesName)
            }
            if let episodeText {
                insightRow(title: "Épisode", value: episodeText)
            }
            if let year = item?.year {
                insightRow(title: "Année", value: String(year))
            }
            insightRow(title: "Qualité", value: qualityLabel)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: metrics.panelWidth, alignment: .leading)
        .nativePlayerTrackMenuGlass(cornerRadius: metrics.cornerRadius)
        .background(alignment: .topLeading) {
            if TVLiveUIAutomationPolicy.isEnabledForCurrentProcess {
                PlayerAccessibilityMarkerView(identifier: "native_player_insight_panel")
                    .frame(width: 1, height: 1)
            }
        }
    }

    private func insightRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: metrics.sectionTitleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: metrics.rowTitleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }

    private var episodeText: String? {
        switch (item?.parentIndexNumber, item?.indexNumber) {
        case let (.some(season), .some(episode)): return "S\(season), E\(episode)"
        case let (.some(season), .none): return "S\(season)"
        case let (.none, .some(episode)): return "E\(episode)"
        case (.none, .none): return nil
        }
    }

    private var metrics: NativePlayerTrackMenuLayout { .current }
}

#if !os(tvOS)
private struct NativePlayerTrackMenuRow: View {
    let option: PlaybackTrackOption
    let focusedOptionID: FocusState<String?>.Binding
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.system(size: metrics.rowTitleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if let details = presentation.details {
                        Text(details)
                            .font(.system(size: metrics.badgeSize, weight: .medium, design: .rounded))
                            .foregroundStyle(foreground.opacity(isFocused ? 0.68 : 0.52))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark")
                    .font(.system(size: metrics.checkSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(option.isSelected ? foreground.opacity(0.92) : .clear)
                    .frame(width: metrics.checkColumnWidth)
            }
            .padding(.horizontal, metrics.rowHorizontalPadding)
            .frame(height: metrics.rowHeight)
            .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(rowFillOpacity))
                    .glassEffect(.clear.interactive(), in: .rect(cornerRadius: rowCornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(rowStrokeOpacity), lineWidth: 1)
            }
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .focused(focusedOptionID, equals: option.id)
        .nativePlayerTrackMenuFocusDisabled()
        .padding(.horizontal, metrics.rowOuterPadding)
        .accessibilityIdentifier("native_player_track_option")
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityValue(option.isSelected ? "selected" : "not_selected")
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }

    private var isFocused: Bool {
        focusedOptionID.wrappedValue == option.id
    }

    private var foreground: Color {
        isFocused ? Color.black.opacity(0.86) : Color.white.opacity(0.96)
    }

    private var rowFillOpacity: Double {
        if isFocused { return style.focusedFillOpacity }
        if option.isSelected { return style.selectedFillOpacity }
        return style.restingFillOpacity
    }

    private var rowStrokeOpacity: Double {
        if isFocused { return style.focusedStrokeOpacity }
        if option.isSelected { return style.selectedStrokeOpacity }
        return style.restingStrokeOpacity
    }

    private var metrics: NativePlayerTrackMenuLayout {
        NativePlayerTrackMenuLayout.current
    }

    private var style: NativePlayerTrackMenuVisualStyle {
        NativePlayerTrackMenuVisualStyle.current
    }

    private var presentation: PlaybackTrackMenuOptionPresentation {
        PlaybackTrackMenuOptionPresentation(option: option)
    }

    private var rowCornerRadius: CGFloat { metrics.rowHeight * 0.32 }
}

private struct NativePlayerTrackMenuEmptyRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: NativePlayerTrackMenuLayout.current.rowTitleSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, NativePlayerTrackMenuLayout.current.horizontalPadding)
            .frame(height: NativePlayerTrackMenuLayout.current.rowHeight)
            .accessibilityLabel(title)
    }
}
#endif

struct NativePlayerTrackMenuLayout {
    let panelWidth: CGFloat
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let sectionSpacing: CGFloat
    let rowSpacing: CGFloat
    let rowHeight: CGFloat
    let rowOuterPadding: CGFloat
    let rowHorizontalPadding: CGFloat
    let checkColumnWidth: CGFloat
    let titleSize: CGFloat
    let sectionTitleSize: CGFloat
    let rowTitleSize: CGFloat
    let badgeSize: CGFloat
    let checkSize: CGFloat
    let contentMaxHeight: CGFloat

    static let tvOS = NativePlayerTrackMenuLayout(
        panelWidth: 460,
        cornerRadius: 28,
        horizontalPadding: 24,
        verticalPadding: 20,
        sectionSpacing: 14,
        rowSpacing: 6,
        rowHeight: 58,
        rowOuterPadding: 10,
        rowHorizontalPadding: 16,
        checkColumnWidth: 28,
        titleSize: 24,
        sectionTitleSize: 20,
        rowTitleSize: 22,
        badgeSize: 15,
        checkSize: 18,
        contentMaxHeight: 360
    )

    static let iOS = NativePlayerTrackMenuLayout(
        panelWidth: 320,
        cornerRadius: 30,
        horizontalPadding: 24,
        verticalPadding: 20,
        sectionSpacing: 16,
        rowSpacing: 6,
        rowHeight: 50,
        rowOuterPadding: 10,
        rowHorizontalPadding: 18,
        checkColumnWidth: 28,
        titleSize: 21,
        sectionTitleSize: 18,
        rowTitleSize: 21,
        badgeSize: 12,
        checkSize: 18,
        contentMaxHeight: 250
    )

    static var current: NativePlayerTrackMenuLayout {
#if os(tvOS)
        tvOS
#else
        iOS
#endif
    }
}

struct NativePlayerTrackMenuVisualStyle: Equatable {
    let panelOpaqueFillOpacity: Double
    let panelBlackTintOpacity: Double
    let focusedFillOpacity: Double
    let selectedFillOpacity: Double
    let restingFillOpacity: Double
    let focusedStrokeOpacity: Double
    let selectedStrokeOpacity: Double
    let restingStrokeOpacity: Double

    static let tvOS = NativePlayerTrackMenuVisualStyle(
        panelOpaqueFillOpacity: 0,
        panelBlackTintOpacity: 0.08,
        focusedFillOpacity: 0.28,
        selectedFillOpacity: 0.055,
        restingFillOpacity: 0.012,
        focusedStrokeOpacity: 0.16,
        selectedStrokeOpacity: 0.08,
        restingStrokeOpacity: 0.025
    )

    static let iOS = NativePlayerTrackMenuVisualStyle(
        panelOpaqueFillOpacity: 0,
        panelBlackTintOpacity: 0.06,
        focusedFillOpacity: 0.20,
        selectedFillOpacity: 0.05,
        restingFillOpacity: 0.01,
        focusedStrokeOpacity: 0.12,
        selectedStrokeOpacity: 0.07,
        restingStrokeOpacity: 0.02
    )

    static var current: NativePlayerTrackMenuVisualStyle {
#if os(tvOS)
        tvOS
#else
        iOS
#endif
    }
}

private extension View {
#if !os(tvOS)
    func nativePlayerTrackMenuFocusScope(_ namespace: Namespace.ID) -> some View {
        self
    }

    func nativePlayerPrefersDefaultTrackFocus(_ enabled: Bool, in namespace: Namespace.ID) -> some View {
        self
    }
#endif

    func nativePlayerTrackMenuGlass(cornerRadius: CGFloat) -> some View {
        let style = NativePlayerTrackMenuVisualStyle.current
        return self
        .glassEffect(
            .regular.tint(.black.opacity(style.panelBlackTintOpacity)),
            in: .rect(cornerRadius: cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
    }

#if !os(tvOS)
    func nativePlayerTrackMenuFocusDisabled() -> some View {
        self
    }
#endif
}

/// A sheet that lets the user switch audio language and subtitle tracks
/// for the current playback session.
///
/// Audio switching is backed by `PlaybackSessionController.selectAudioTrack(id:)`,
/// which first tries a native AVMediaSelectionGroup switch (embedded multi-track
/// containers) and falls back to a seamless DirectPlay reload with the desired
/// `AudioStreamIndex`.
///
/// Subtitle switching uses `selectSubtitleTrack(id:)`, which similarly tries
/// the native legible group before falling back to an HLS reload with
/// `SubtitleStreamIndex=N&SubtitleMethod=Hls` so Jellyfin can embed the
/// sidecar subtitle track in the manifest.
struct TrackPickerView: View {
    let controls: PlaybackControlsModel
    let onSelect: (PlaybackControlSelection) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // ── Audio ────────────────────────────────────────────────
                if !controls.audioOptions.isEmpty {
                    Section {
                        ForEach(controls.audioOptions) { option in
                            TrackRow(
                                title: option.title,
                                badge: option.badge,
                                isSelected: option.isSelected
                            ) {
                                guard let trackID = option.trackID else { return }
                                select(.audio(trackID))
                            }
                        }
                    } header: {
                        Label("Piste audio", systemImage: "speaker.wave.2")
                    }
                }

                // ── Subtitles ────────────────────────────────────────────
                if !controls.subtitleOptions.isEmpty {
                    Section {
                        ForEach(controls.subtitleOptions) { option in
                            TrackRow(
                                title: option.title,
                                badge: option.badge,
                                icon: option.iconName,
                                isSelected: option.isSelected
                            ) {
                                select(.subtitle(option.trackID))
                            }
                        }
                    } header: {
                        Label("Sous-titres", systemImage: "captions.bubble")
                    }
                }
            }
            .navigationTitle("Pistes")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
        .accessibilityIdentifier("player_track_picker_sheet")
    }

    private func select(_ selection: PlaybackControlSelection) {
        onSelect(selection)
        dismiss()
    }
}

// MARK: - Track Row

private struct TrackRow: View {
    let title: String
    let badge: String?
    var icon: String? = nil
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)

                    if let badge {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

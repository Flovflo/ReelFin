import Shared
import SwiftUI

struct NativePlayerAVKitMenuLayout: Equatable {
    let width: CGFloat = 600
    let cornerRadius: CGFloat = 44
    let horizontalInset: CGFloat = 54
    let verticalInset: CGFloat = 42
    let headerSize: CGFloat = 30
    let primarySize: CGFloat = 34
    let secondarySize: CGFloat = 22
    let choiceHeight: CGFloat = 68
    let navigationHeight: CGFloat = 108
    let rowSpacing: CGFloat = 2
    let dividerExtent: CGFloat = 21
    let maximumContentHeight: CGFloat = 520
    let focusOpacity: Double = 0.20
    let selectedOpacity: Double = 0.045
    let opaqueBackgroundOpacity: Double = 0

    static let standard = Self()

    func contentHeight(
        choiceRowCount: Int,
        navigationRowCount: Int = 0,
        dividerCount: Int = 0
    ) -> CGFloat {
        let choices = max(0, choiceRowCount)
        let navigation = max(0, navigationRowCount)
        let dividers = max(0, dividerCount)
        let elementCount = choices + navigation + dividers
        let total = CGFloat(choices) * choiceHeight
            + CGFloat(navigation) * navigationHeight
            + CGFloat(dividers) * dividerExtent
            + CGFloat(max(0, elementCount - 1)) * rowSpacing
        return min(total, maximumContentHeight)
    }
}

enum NativePlayerAVKitMenuPlatform {
    case iOS
    case tvOS
}

enum NativePlayerAVKitMenuPresentationPolicy {
    static func usesReplica(on platform: NativePlayerAVKitMenuPlatform) -> Bool {
        platform == .tvOS
    }
}

enum NativePlayerAVKitMenuAction: Equatable {
    case selectAudio(String)
    case enableSubtitles
    case disableSubtitles
    case openLanguages
    case openStyles
    case selectSubtitle(String)
    case selectStyle(SubtitleBackgroundStyle)

    static func forRow(_ row: NativePlayerAVKitMenuRowID) -> Self {
        switch row {
        case let .audio(trackID):
            return .selectAudio(trackID)
        case .subtitleOn:
            return .enableSubtitles
        case .subtitleOff:
            return .disableSubtitles
        case .subtitleLanguage:
            return .openLanguages
        case .subtitleStyle:
            return .openStyles
        case let .subtitleTrack(trackID):
            return .selectSubtitle(trackID)
        case let .style(style):
            return .selectStyle(style)
        }
    }
}

enum NativePlayerAVKitMenuExitResult: Equatable {
    case returnedToRoot
    case dismissed
}

enum NativePlayerAVKitMenuMoveDirection: Equatable {
    case up
    case down
    case left
    case right
}

enum NativePlayerAVKitMenuMoveResult: Equatable {
    case movedFocus(NativePlayerAVKitMenuRowID)
    case openedSubmenu
    case returnedToRoot
    case ignored
}

struct NativePlayerAVKitMenuState: Equatable {
    var page: NativePlayerAVKitMenuPage
    var focusedRow: NativePlayerAVKitMenuRowID?

    init(
        page: NativePlayerAVKitMenuPage,
        focusedRow: NativePlayerAVKitMenuRowID? = nil
    ) {
        self.page = page
        self.focusedRow = focusedRow
    }

    mutating func perform(_ action: NativePlayerAVKitMenuAction) {
        switch action {
        case .openLanguages:
            page = .subtitleLanguages
            focusedRow = nil
        case .openStyles:
            page = .subtitleStyles
            focusedRow = nil
        case .selectSubtitle:
            page = .subtitlesRoot
            focusedRow = .subtitleLanguage
        case .selectStyle:
            page = .subtitlesRoot
            focusedRow = .subtitleStyle
        case .selectAudio, .enableSubtitles, .disableSubtitles:
            break
        }
    }

    mutating func handleMenu() -> NativePlayerAVKitMenuExitResult {
        guard returnToParent() else { return .dismissed }
        return .returnedToRoot
    }

    mutating func handleLeft() -> Bool {
        returnToParent()
    }

    mutating func handleMove(
        _ direction: NativePlayerAVKitMenuMoveDirection,
        from current: NativePlayerAVKitMenuRowID?,
        rows: [NativePlayerAVKitMenuRowID]
    ) -> NativePlayerAVKitMenuMoveResult {
        switch direction {
        case .up, .down:
            guard let anchor = current ?? focusedRow ?? rows.first else {
                return .ignored
            }
            let next = NativePlayerAVKitMenuFocusPolicy.move(
                from: anchor,
                delta: direction == .up ? -1 : 1,
                rows: rows
            )
            focusedRow = next
            return .movedFocus(next)

        case .left:
            return handleLeft() ? .returnedToRoot : .ignored

        case .right:
            switch current ?? focusedRow {
            case .subtitleLanguage:
                perform(.openLanguages)
                return .openedSubmenu
            case .subtitleStyle:
                perform(.openStyles)
                return .openedSubmenu
            default:
                return .ignored
            }
        }
    }

    private mutating func returnToParent() -> Bool {
        let origin: NativePlayerAVKitMenuRowID
        switch page {
        case .subtitleLanguages:
            origin = .subtitleLanguage
        case .subtitleStyles:
            origin = .subtitleStyle
        case .audio, .subtitlesRoot:
            return false
        }
        guard let parent = NativePlayerAVKitMenuFocusPolicy.parent(of: page) else {
            return false
        }
        page = parent
        focusedRow = origin
        return true
    }
}

enum NativePlayerAVKitMenuDispatch {
    static func dispatch(
        _ selection: PlaybackControlSelection,
        to handler: (PlaybackControlSelection) -> Void
    ) {
        handler(selection)
    }
}

enum NativePlayerAVKitMenuRouteCoordinator {
    static func selectAndDismiss(
        _ selection: PlaybackControlSelection,
        onSelect: (PlaybackControlSelection) -> Void,
        onDismiss: () -> Void
    ) {
        NativePlayerAVKitMenuDispatch.dispatch(selection, to: onSelect)
        onDismiss()
    }
}

struct NativePlayerAVKitMenuView: View {
    let mode: PlaybackTrackMenuKind
    let controls: PlaybackControlsModel
    let subtitleStyle: SubtitleBackgroundStyle
    let lastEnabledSubtitleID: String?
    let onSelect: (PlaybackControlSelection) -> Void
    let onSelectStyle: (SubtitleBackgroundStyle) -> Void
    let onDismiss: () -> Void

    @State private var menuState: NativePlayerAVKitMenuState
    @State private var focusRequestToken: UInt = 0
    @FocusState private var focusedRow: NativePlayerAVKitMenuRowID?
    @Namespace private var focusNamespace

    init(
        mode: PlaybackTrackMenuKind,
        controls: PlaybackControlsModel,
        subtitleStyle: SubtitleBackgroundStyle,
        lastEnabledSubtitleID: String?,
        onSelect: @escaping (PlaybackControlSelection) -> Void,
        onSelectStyle: @escaping (SubtitleBackgroundStyle) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.controls = controls
        self.subtitleStyle = subtitleStyle
        self.lastEnabledSubtitleID = lastEnabledSubtitleID
        self.onSelect = onSelect
        self.onSelectStyle = onSelectStyle
        self.onDismiss = onDismiss
        _menuState = State(
            initialValue: NativePlayerAVKitMenuState(
                page: mode == .audio ? .audio : .subtitlesRoot
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: layout.headerSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            ScrollView {
                VStack(alignment: .leading, spacing: layout.rowSpacing) {
                    rows
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: contentHeight)
        }
        .padding(.horizontal, layout.horizontalInset)
        .padding(.vertical, layout.verticalInset)
        .frame(width: layout.width)
        .glassEffect(
            .regular.tint(.black.opacity(0.08)),
            in: .rect(cornerRadius: layout.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .nativePlayerAVKitMenuFocusScope(focusNamespace)
        .defaultFocus($focusedRow, preferredFocusedRow)
        .background(alignment: .topLeading) {
            if TVLiveUIAutomationPolicy.isEnabledForCurrentProcess {
                ZStack {
                    PlayerAccessibilityMarkerView(identifier: accessibilityIdentifier)
                    PlayerAccessibilityMarkerView(identifier: accessibilityPageIdentifier)
                    PlayerAccessibilityMarkerView(
                        identifier: "native_player_track_focused_title",
                        value: focusedRowTitle
                    )
                    PlayerAccessibilityMarkerView(
                        identifier: "native_player_track_menu_page",
                        value: accessibilityPage
                    )
                }
                .frame(width: 1, height: 1)
            }
        }
#if os(tvOS)
        .onExitCommand {
            if menuState.handleMenu() == .returnedToRoot {
                advanceFocusRequest()
            } else {
                onDismiss()
            }
        }
#endif
    }

    @ViewBuilder
    private var rows: some View {
        switch menuState.page {
        case .audio:
            ForEach(realAudioOptions) { option in
                let rowID = NativePlayerAVKitMenuRowID.audio(option.id)
                NativePlayerAVKitChoiceRow(
                    title: presentation(for: option).title,
                    detail: presentation(for: option).details,
                    isSelected: option.isSelected,
                    isFocused: focusedRow == rowID,
                    layout: layout
                ) {
                    perform(.forRow(rowID))
                }
                .focused($focusedRow, equals: rowID)
                .nativePlayerAVKitMenuMoveCommands { direction in
                    handleMoveCommand(direction, from: rowID)
                }
                .nativePlayerAVKitMenuDefaultFocus(
                    rowID == preferredFocusedRow,
                    in: focusNamespace
                )
                .task(id: focusRequestID) {
                    await requestFocus(on: rowID)
                }
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityValue(option.isSelected ? "selected" : "not_selected")
                .accessibilityAddTraits(option.isSelected ? .isSelected : [])
            }

        case .subtitlesRoot:
            if !realSubtitleOptions.isEmpty {
                rootChoiceRow(
                    id: .subtitleOn,
                    title: "On",
                    isSelected: selectedSubtitleID != nil
                )
                rootChoiceRow(
                    id: .subtitleOff,
                    title: "Off",
                    isSelected: selectedSubtitleID == nil
                )

                Divider()
                    .overlay(.white.opacity(0.12))
                    .padding(.vertical, 10)

                navigationRow(
                    id: .subtitleLanguage,
                    title: "Language",
                    detail: selectedSubtitlePresentation?.title ?? "None"
                )
                navigationRow(
                    id: .subtitleStyle,
                    title: "Style",
                    detail: subtitleStyle.displayName
                )
            }

        case .subtitleLanguages:
            ForEach(realSubtitleOptions) { option in
                let rowID = NativePlayerAVKitMenuRowID.subtitleTrack(option.id)
                NativePlayerAVKitChoiceRow(
                    title: presentation(for: option).title,
                    detail: presentation(for: option).details,
                    isSelected: option.trackID == preferredSubtitleID,
                    isFocused: focusedRow == rowID,
                    layout: layout
                ) {
                    perform(.forRow(rowID))
                }
                .focused($focusedRow, equals: rowID)
                .nativePlayerAVKitMenuMoveCommands { direction in
                    handleMoveCommand(direction, from: rowID)
                }
                .nativePlayerAVKitMenuDefaultFocus(
                    rowID == preferredFocusedRow,
                    in: focusNamespace
                )
                .task(id: focusRequestID) {
                    await requestFocus(on: rowID)
                }
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityValue(option.trackID == preferredSubtitleID ? "selected" : "not_selected")
                .accessibilityAddTraits(option.trackID == preferredSubtitleID ? .isSelected : [])
            }

        case .subtitleStyles:
            ForEach(SubtitleBackgroundStyle.allCases, id: \.self) { style in
                let rowID = NativePlayerAVKitMenuRowID.style(style)
                NativePlayerAVKitChoiceRow(
                    title: style.displayName,
                    detail: nil,
                    isSelected: style == subtitleStyle,
                    isFocused: focusedRow == rowID,
                    layout: layout
                ) {
                    perform(.forRow(rowID))
                }
                .focused($focusedRow, equals: rowID)
                .nativePlayerAVKitMenuMoveCommands { direction in
                    handleMoveCommand(direction, from: rowID)
                }
                .nativePlayerAVKitMenuDefaultFocus(
                    rowID == preferredFocusedRow,
                    in: focusNamespace
                )
                .task(id: focusRequestID) {
                    await requestFocus(on: rowID)
                }
                .accessibilityLabel(style.displayName)
                .accessibilityValue(style == subtitleStyle ? "selected" : "not_selected")
                .accessibilityAddTraits(style == subtitleStyle ? .isSelected : [])
            }
        }
    }

    private func rootChoiceRow(
        id: NativePlayerAVKitMenuRowID,
        title: String,
        isSelected: Bool
    ) -> some View {
        NativePlayerAVKitChoiceRow(
            title: title,
            detail: nil,
            isSelected: isSelected,
            isFocused: focusedRow == id,
            layout: layout
        ) {
            perform(.forRow(id))
        }
        .focused($focusedRow, equals: id)
        .nativePlayerAVKitMenuMoveCommands { direction in
            handleMoveCommand(direction, from: id)
        }
        .nativePlayerAVKitMenuDefaultFocus(id == preferredFocusedRow, in: focusNamespace)
        .task(id: focusRequestID) {
            await requestFocus(on: id)
        }
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "selected" : "not_selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func navigationRow(
        id: NativePlayerAVKitMenuRowID,
        title: String,
        detail: String
    ) -> some View {
        NativePlayerAVKitNavigationRow(
            title: title,
            detail: detail,
            isFocused: focusedRow == id,
            layout: layout
        ) {
            perform(.forRow(id))
        }
        .focused($focusedRow, equals: id)
        .nativePlayerAVKitMenuMoveCommands { direction in
            handleMoveCommand(direction, from: id)
        }
        .nativePlayerAVKitMenuDefaultFocus(id == preferredFocusedRow, in: focusNamespace)
        .task(id: focusRequestID) {
            await requestFocus(on: id)
        }
        .accessibilityLabel("\(title), \(detail)")
    }

    private func perform(_ action: NativePlayerAVKitMenuAction) {
        switch action {
        case let .selectAudio(trackID):
            NativePlayerAVKitMenuRouteCoordinator.selectAndDismiss(
                .audio(trackID),
                onSelect: onSelect,
                onDismiss: onDismiss
            )

        case .enableSubtitles:
            guard let trackID = NativePlayerSubtitleMenuPolicy.enabledTrackID(
                options: controls.subtitleOptions,
                lastEnabledID: lastEnabledSubtitleID
            ) else { return }
            NativePlayerAVKitMenuDispatch.dispatch(.subtitle(trackID), to: onSelect)

        case .disableSubtitles:
            NativePlayerAVKitMenuDispatch.dispatch(.subtitle(nil), to: onSelect)

        case .openLanguages:
            menuState.perform(action)
            advanceFocusRequest()

        case .openStyles:
            menuState.perform(action)
            advanceFocusRequest()

        case let .selectSubtitle(trackID):
            NativePlayerAVKitMenuDispatch.dispatch(.subtitle(trackID), to: onSelect)
            menuState.perform(action)
            advanceFocusRequest()

        case let .selectStyle(style):
            onSelectStyle(style)
            menuState.perform(action)
            advanceFocusRequest()
        }
    }

    private var realAudioOptions: [PlaybackTrackOption] {
        controls.audioOptions.filter { $0.trackID != nil }
    }

    private var realSubtitleOptions: [PlaybackTrackOption] {
        controls.subtitleOptions.filter { $0.trackID != nil }
    }

    private var selectedSubtitleID: String? {
        realSubtitleOptions.first(where: \.isSelected)?.trackID
    }

    private var preferredSubtitleID: String? {
        NativePlayerSubtitleMenuPolicy.enabledTrackID(
            options: controls.subtitleOptions,
            lastEnabledID: lastEnabledSubtitleID
        )
    }

    private var selectedSubtitlePresentation: PlaybackTrackMenuOptionPresentation? {
        let option = realSubtitleOptions.first(where: { $0.trackID == preferredSubtitleID })
            ?? realSubtitleOptions.first
        return option.map(presentation(for:))
    }

    private var preferredFocusedRow: NativePlayerAVKitMenuRowID {
        if let focusedRow = menuState.focusedRow,
           availableRowIDs.contains(focusedRow) {
            return focusedRow
        }
        switch menuState.page {
        case .audio:
            let option = realAudioOptions.first(where: \.isSelected) ?? realAudioOptions.first
            return .audio(option?.id ?? "__empty_audio__")
        case .subtitlesRoot:
            return selectedSubtitleID == nil ? .subtitleOff : .subtitleOn
        case .subtitleLanguages:
            let option = realSubtitleOptions.first(where: { $0.trackID == preferredSubtitleID })
                ?? realSubtitleOptions.first
            return .subtitleTrack(option?.id ?? "__empty_subtitle__")
        case .subtitleStyles:
            return .style(subtitleStyle)
        }
    }

    private var availableRowIDs: [NativePlayerAVKitMenuRowID] {
        switch menuState.page {
        case .audio:
            return realAudioOptions.map { .audio($0.id) }
        case .subtitlesRoot:
            return menuState.page.rowIDs
        case .subtitleLanguages:
            return realSubtitleOptions.map { .subtitleTrack($0.id) }
        case .subtitleStyles:
            return SubtitleBackgroundStyle.allCases.map { .style($0) }
        }
    }

    private var focusedRowTitle: String? {
        guard let focusedRow else { return nil }
        switch focusedRow {
        case let .audio(trackID):
            return realAudioOptions.first(where: { $0.id == trackID })?.accessibilityLabel
        case .subtitleOn:
            return "On"
        case .subtitleOff:
            return "Off"
        case .subtitleLanguage:
            return "Language"
        case .subtitleStyle:
            return "Style"
        case let .subtitleTrack(trackID):
            return realSubtitleOptions.first(where: { $0.id == trackID })?.accessibilityLabel
        case let .style(style):
            return style.displayName
        }
    }

    private var title: String {
        switch menuState.page {
        case .audio:
            return "Audio Track"
        case .subtitlesRoot:
            return "Subtitles"
        case .subtitleLanguages:
            return "Language"
        case .subtitleStyles:
            return "Style"
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

    private var accessibilityPage: String {
        switch menuState.page {
        case .audio: return "audio"
        case .subtitlesRoot: return "subtitles_root"
        case .subtitleLanguages: return "subtitle_languages"
        case .subtitleStyles: return "subtitle_styles"
        }
    }

    private var accessibilityPageIdentifier: String {
        switch menuState.page {
        case .audio: return "native_player_avkit_audio_menu"
        case .subtitlesRoot: return "native_player_avkit_subtitles_root"
        case .subtitleLanguages: return "native_player_avkit_subtitle_languages"
        case .subtitleStyles: return "native_player_avkit_subtitle_styles"
        }
    }

    private var focusRequestID: String {
        let page: String
        switch menuState.page {
        case .audio: page = "audio"
        case .subtitlesRoot: page = "subtitles-root"
        case .subtitleLanguages: page = "subtitle-languages"
        case .subtitleStyles: page = "subtitle-styles"
        }
        return "\(page)-\(focusRequestToken)"
    }

    private func presentation(
        for option: PlaybackTrackOption
    ) -> PlaybackTrackMenuOptionPresentation {
        PlaybackTrackMenuOptionPresentation(option: option)
    }

    private var layout: NativePlayerAVKitMenuLayout { .standard }

    private var contentHeight: CGFloat {
        switch menuState.page {
        case .audio:
            return layout.contentHeight(choiceRowCount: realAudioOptions.count)
        case .subtitlesRoot:
            guard !realSubtitleOptions.isEmpty else { return 0 }
            return layout.contentHeight(
                choiceRowCount: 2,
                navigationRowCount: 2,
                dividerCount: 1
            )
        case .subtitleLanguages:
            return layout.contentHeight(choiceRowCount: realSubtitleOptions.count)
        case .subtitleStyles:
            return layout.contentHeight(choiceRowCount: SubtitleBackgroundStyle.allCases.count)
        }
    }

    private func handleMoveCommand(
        _ direction: NativePlayerAVKitMenuMoveDirection,
        from sourceRow: NativePlayerAVKitMenuRowID
    ) {
        let result = menuState.handleMove(
            direction,
            from: sourceRow,
            rows: availableRowIDs
        )
        if case let .movedFocus(row) = result {
            focusedRow = row
        } else if result == .openedSubmenu || result == .returnedToRoot {
            advanceFocusRequest()
        }
    }

    private func advanceFocusRequest() {
        focusRequestToken &+= 1
    }

    private func requestFocus(on row: NativePlayerAVKitMenuRowID) async {
        guard row == preferredFocusedRow else { return }
        await Task.yield()
        guard !Task.isCancelled,
              row == preferredFocusedRow,
              availableRowIDs.contains(row) else { return }
        focusedRow = row
        await Task.yield()
        guard !Task.isCancelled,
              row == preferredFocusedRow,
              availableRowIDs.contains(row) else { return }
        focusedRow = row
    }
}

private struct NativePlayerAVKitChoiceRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let isFocused: Bool
    let layout: NativePlayerAVKitMenuLayout
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.96) : .clear)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: layout.primarySize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if let detail {
                        Text(detail)
                            .font(.system(size: layout.secondarySize, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: layout.choiceHeight)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(rowOpacity))
            }
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .nativePlayerAVKitMenuFocusChromeDisabled()
    }

    private var rowOpacity: Double {
        if isFocused { return layout.focusOpacity }
        if isSelected { return layout.selectedOpacity }
        return layout.opaqueBackgroundOpacity
    }
}

private struct NativePlayerAVKitNavigationRow: View {
    let title: String
    let detail: String
    let isFocused: Bool
    let layout: NativePlayerAVKitMenuLayout
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: layout.primarySize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: layout.secondarySize, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 18)
            .frame(height: layout.navigationHeight)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(isFocused ? layout.focusOpacity : layout.opaqueBackgroundOpacity))
            }
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .nativePlayerAVKitMenuFocusChromeDisabled()
    }
}

private extension View {
    @ViewBuilder
    func nativePlayerAVKitMenuFocusScope(_ namespace: Namespace.ID) -> some View {
#if os(tvOS)
        self
            .focusScope(namespace)
            .focusSection()
#else
        self
#endif
    }

    @ViewBuilder
    func nativePlayerAVKitMenuDefaultFocus(
        _ enabled: Bool,
        in namespace: Namespace.ID
    ) -> some View {
#if os(tvOS)
        self.prefersDefaultFocus(enabled, in: namespace)
#else
        self
#endif
    }

    @ViewBuilder
    func nativePlayerAVKitMenuFocusChromeDisabled() -> some View {
#if os(tvOS)
        self
            .focusEffectDisabled(true)
            .hoverEffectDisabled(true)
#else
        self
#endif
    }

    @ViewBuilder
    func nativePlayerAVKitMenuMoveCommands(
        _ action: @escaping (NativePlayerAVKitMenuMoveDirection) -> Void
    ) -> some View {
#if os(tvOS)
        self.onMoveCommand { direction in
            switch direction {
            case .up:
                action(.up)
            case .down:
                action(.down)
            case .left:
                action(.left)
            case .right:
                action(.right)
            @unknown default:
                break
            }
        }
#else
        self
#endif
    }
}

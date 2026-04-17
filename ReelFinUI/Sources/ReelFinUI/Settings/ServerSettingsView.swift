import PlaybackEngine
import Shared
import SwiftUI

struct ServerSettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel: ServerSettingsViewModel
    private let metadata = AppMetadata.current
    let onLogout: () -> Void

    init(dependencies: ReelFinDependencies, onLogout: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ServerSettingsViewModel(dependencies: dependencies))
        self.onLogout = onLogout
    }

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        iosBody
        #endif
    }

    #if os(tvOS)
    private var tvBody: some View {
        ZStack {
            settingsBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .reelFinTitleStyle()

                    Text("Playback and server preferences that affect ReelFin immediately.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))

                    if let error = viewModel.errorMessage {
                        SettingsStatusBanner(text: error, tone: .error)
                    } else if let info = viewModel.infoMessage {
                        SettingsStatusBanner(text: info, tone: .success)
                    }

                    tvSection(title: "Account") {
                        tvInfoRow(title: "User", value: viewModel.displayUsername)
                        tvInfoRow(title: "Server", value: viewModel.displayServerHost)
                    }

                    tvSection(title: "Playback") {
                        tvMenuRow(
                            title: "Streaming Quality",
                            value: viewModel.preferredQuality.settingsLabel
                        ) {
                            ForEach(QualityPreference.allCases, id: \.self) { quality in
                                Button {
                                    viewModel.preferredQuality = quality
                                } label: {
                                    Text(quality.settingsLabel)
                                }
                            }
                        }

                        tvMenuRow(
                            title: "Video Mode",
                            value: viewModel.playbackPolicy.settingsLabel
                        ) {
                            ForEach(PlaybackPolicy.allCases, id: \.self) { policy in
                                Button {
                                    viewModel.playbackPolicy = policy
                                } label: {
                                    Text(policy.settingsLabel)
                                }
                            }
                        }

                        Toggle(isOn: $viewModel.preferAudioTranscodeOnly) {
                            Text("Prefer audio-only transcode when possible")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .tint(.white)

                        Toggle(isOn: $viewModel.forceH264FallbackWhenNotDirectPlay) {
                            Text("Use H.264 compatibility fallback")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .tint(.white)
                    }

                    tvSection(title: "Notifications") {
                        Toggle(
                            isOn: Binding(
                                get: { viewModel.episodeReleaseNotificationsEnabled },
                                set: { newValue in
                                    viewModel.episodeReleaseNotificationsEnabled = newValue
                                    Task {
                                        await viewModel.setEpisodeReleaseNotificationsEnabled(newValue)
                                    }
                                }
                            )
                        ) {
                            Text("New Episode Alerts")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .tint(.white)
                    }

                    tvSection(title: "Server") {
                        TextField("https://your-jellyfin-server", text: $viewModel.serverURLText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 10) {
                        Button("Test Connection") {
                            runConnectionTest()
                        }
                        .buttonStyle(SettingsActionButtonStyle(primary: false))

                        Button(viewModel.saveButtonTitle) {
                            persistSettings()
                        }
                        .buttonStyle(SettingsActionButtonStyle(primary: true))
                        .disabled(!viewModel.canSave || !viewModel.hasPendingChanges)
                    }

                    Button("Sign Out") {
                        onLogout()
                    }
                    .buttonStyle(SettingsActionButtonStyle(primary: false))

                    if metadata.hasSupportSurface {
                        tvSection(title: "Legal & Support") {
                            if let privacyPolicyURL = metadata.privacyPolicyURL {
                                legacySupportLinkButton(title: "Privacy Policy", subtitle: privacyPolicyURL.absoluteString) {
                                    openURL(privacyPolicyURL)
                                }
                            }

                            if let termsOfServiceURL = metadata.termsOfServiceURL {
                                legacySupportLinkButton(title: "Terms of Service", subtitle: termsOfServiceURL.absoluteString) {
                                    openURL(termsOfServiceURL)
                                }
                            }

                            if let supportURL = metadata.supportURL {
                                legacySupportLinkButton(title: "Support", subtitle: supportURL.absoluteString) {
                                    openURL(supportURL)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.refreshEpisodeReleaseNotificationsState()
        }
    }
    #endif

    #if os(tvOS)
    private var settingsBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.09),
                    Color(red: 0.02, green: 0.03, blue: 0.05),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.16, green: 0.46, blue: 0.78).opacity(0.25),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )
            .offset(x: -100, y: -80)

            RadialGradient(
                colors: [
                    Color(red: 0.18, green: 0.74, blue: 0.68).opacity(0.16),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            .offset(x: 120, y: -120)
        }
    }
    #endif

    #if !os(tvOS)
    private var iosBody: some View {
        ZStack {
            settingsBackground.ignoresSafeArea()

            StickyBlurHeader(
                maxBlurRadius: 18,
                fadeExtension: 96,
                tintOpacityTop: 0.62,
                tintOpacityMiddle: 0.18
            ) { _ in
                headerBlock
                    .frame(maxWidth: 780, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, stickyHeaderTopPadding)
                    .padding(.bottom, 18)
                    .accessibilityIdentifier("settings_sticky_blur_header")
            } content: {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.errorMessage != nil || viewModel.infoMessage != nil {
                        statusBanner
                    }

                    accountCard
                    homeDiscoveryCard
                    playbackCard
                    notificationsCard
                    serverCard
                    advancedPlaybackCard
                    aboutCard
                    signOutButton
                }
                .frame(maxWidth: 780, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 128)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.refreshEpisodeReleaseNotificationsState()
        }
    }

    private var settingsBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.09),
                    Color(red: 0.02, green: 0.03, blue: 0.05),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.16, green: 0.46, blue: 0.78).opacity(0.25),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )
            .offset(x: -100, y: -80)

            RadialGradient(
                colors: [
                    Color(red: 0.18, green: 0.74, blue: 0.68).opacity(0.16),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
            .offset(x: 120, y: -120)
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Playback, discovery, notifications, and server controls that actually change ReelFin.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    SettingsTag(text: viewModel.connectionStatusLabel)
                    SettingsTag(text: viewModel.preferredQuality.settingsLabel)
                    SettingsTag(text: viewModel.homeCustomizationSummary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SettingsTag(text: viewModel.connectionStatusLabel)
                    HStack(spacing: 10) {
                        SettingsTag(text: viewModel.preferredQuality.settingsLabel)
                        SettingsTag(text: viewModel.homeCustomizationSummary)
                    }
                }
            }
        }
    }

    private var stickyHeaderTopPadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 14
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let error = viewModel.errorMessage {
            SettingsStatusBanner(text: error, tone: .error)
        } else if let info = viewModel.infoMessage {
            SettingsStatusBanner(text: info, tone: .success)
        }
    }

    private var accountCard: some View {
        SettingsSectionCard(
            title: "Account",
            subtitle: "Your current Jellyfin identity and the state this screen is managing."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.16),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.displayUsername)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(viewModel.displayServerHost)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer(minLength: 12)

                    SettingsTag(text: viewModel.connectionStatusLabel)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        SettingsMiniStat(title: "Home", value: "\(viewModel.visibleHomeSectionCount) rails")
                        SettingsMiniStat(title: "Playback", value: viewModel.playbackStrategy.settingsLabel)
                        SettingsMiniStat(title: "Bandwidth", value: viewModel.bandwidthCapSummary)
                    }

                    VStack(spacing: 12) {
                        SettingsMiniStat(title: "Home", value: "\(viewModel.visibleHomeSectionCount) rails")
                        SettingsMiniStat(title: "Playback", value: viewModel.playbackStrategy.settingsLabel)
                        SettingsMiniStat(title: "Bandwidth", value: viewModel.bandwidthCapSummary)
                    }
                }
            }
        }
    }

    private var homeDiscoveryCard: some View {
        SettingsSectionCard(
            title: "Home & Discovery",
            subtitle: "Reorder the rails and decide which sections deserve prime real estate."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("These changes apply immediately to the Home tab.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.homeOrderedSectionKinds.enumerated()), id: \.element) { index, kind in
                        HomeSectionPreferenceRow(
                            kind: kind,
                            isVisible: viewModel.isHomeSectionVisible(kind),
                            canMoveUp: viewModel.canMoveHomeSection(kind, direction: .up),
                            canMoveDown: viewModel.canMoveHomeSection(kind, direction: .down),
                            onVisibilityChange: { isVisible in
                                viewModel.setHomeSectionVisibility(kind, isVisible: isVisible)
                            },
                            onMoveUp: { viewModel.moveHomeSection(kind, direction: .up) },
                            onMoveDown: { viewModel.moveHomeSection(kind, direction: .down) }
                        )

                        if index < viewModel.homeOrderedSectionKinds.count - 1 {
                            SettingsRowDivider()
                        }
                    }
                }

                Button("Reset Home Layout") {
                    viewModel.resetHomeSectionCustomization()
                }
                .buttonStyle(SettingsInlineButtonStyle(primary: false))
            }
        }
    }

    private var playbackCard: some View {
        SettingsSectionCard(
            title: "Playback",
            subtitle: "Tune startup speed, stream quality, language defaults, and recovery behavior."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSubsectionHeader(
                    title: "Streaming",
                    subtitle: "These values are saved with your server profile and applied the next time playback is resolved."
                )

                VStack(spacing: 0) {
                    qualityMenuRow
                    SettingsRowDivider()
                    playbackStrategyMenuRow
                    SettingsRowDivider()
                    bitrateOverrideRow
                }

                SettingsSubsectionHeader(
                    title: "Tracks",
                    subtitle: "Pick the languages ReelFin should prefer before you open the in-player track picker."
                )

                VStack(spacing: 0) {
                    languagePreferenceMenu(
                        title: "Preferred Audio",
                        subtitle: "Start with this audio language when it is available.",
                        selection: $viewModel.preferredAudioLanguage
                    )

                    SettingsRowDivider()

                    languagePreferenceMenu(
                        title: "Forced Subtitles",
                        subtitle: "Auto-pick forced subtitles in this language when the file exposes them.",
                        selection: $viewModel.preferredSubtitleLanguage
                    )
                }

                SettingsSubsectionHeader(
                    title: "Recovery",
                    subtitle: "These options shape how aggressive ReelFin should be when a title needs help to start."
                )

                VStack(spacing: 0) {
                    playbackPolicyMenuRow

                    if viewModel.playbackPolicy == .originalLockHDRDV {
                        SettingsRowDivider()
                        SettingsInfoRow(
                            title: "SDR Fallback",
                            value: "Disabled in Preserve HDR mode"
                        )
                    } else {
                        SettingsRowDivider()
                        SettingsToggleRow(
                            title: "Allow SDR Fallback",
                            subtitle: "When a premium HEVC stream is unstable, let ReelFin fall back to a safer SDR/H.264 route.",
                            isOn: $viewModel.allowSDRFallback
                        )
                    }

                    SettingsRowDivider()

                    SettingsToggleRow(
                        title: "Prefer Audio-Only Transcode",
                        subtitle: "Keep the original video path whenever only the audio codec is incompatible.",
                        isOn: $viewModel.preferAudioTranscodeOnly
                    )

                    SettingsRowDivider()

                    SettingsToggleRow(
                        title: "Aggressive H.264 Compatibility",
                        subtitle: "Use H.264 fallback when titles fail to start cleanly outside Direct Play.",
                        isOn: $viewModel.forceH264FallbackWhenNotDirectPlay
                    )
                }
            }
        }
    }

    private var qualityMenuRow: some View {
        Menu {
            ForEach(QualityPreference.allCases, id: \.self) { quality in
                Button {
                    viewModel.preferredQuality = quality
                } label: {
                    if quality == viewModel.preferredQuality {
                        Label(quality.settingsLabel, systemImage: "checkmark")
                    } else {
                        Text(quality.settingsLabel)
                    }
                }
            }
        } label: {
            SettingsValueRow(
                title: "Streaming Quality",
                subtitle: "Choose the baseline target ReelFin uses when building playback info requests.",
                value: viewModel.preferredQuality.settingsLabel
            )
        }
        .buttonStyle(.plain)
    }

    private var playbackStrategyMenuRow: some View {
        Menu {
            ForEach(PlaybackStrategy.allCases, id: \.self) { strategy in
                Button {
                    viewModel.playbackStrategy = strategy
                } label: {
                    if strategy == viewModel.playbackStrategy {
                        Label(strategy.settingsLabel, systemImage: "checkmark")
                    } else {
                        Text(strategy.settingsLabel)
                    }
                }
            }
        } label: {
            SettingsValueRow(
                title: "Playback Route",
                subtitle: "Decide whether ReelFin can use server transcodes or should stay strict about direct/remux playback.",
                value: viewModel.playbackStrategy.settingsLabel
            )
        }
        .buttonStyle(.plain)
    }

    private var playbackPolicyMenuRow: some View {
        Menu {
            ForEach(PlaybackPolicy.allCases, id: \.self) { policy in
                Button {
                    viewModel.playbackPolicy = policy
                } label: {
                    if policy == viewModel.playbackPolicy {
                        Label(policy.settingsLabel, systemImage: "checkmark")
                    } else {
                        Text(policy.settingsLabel)
                    }
                }
            }
        } label: {
            SettingsValueRow(
                title: "Video Mode",
                subtitle: "Balance startup reliability against original HDR / Dolby Vision fidelity.",
                value: viewModel.playbackPolicy.settingsLabel
            )
        }
        .buttonStyle(.plain)
    }

    private var bitrateOverrideRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsValueRow(
                title: "Custom Bitrate Cap",
                subtitle: "Optional ceiling in Mbps. Leave blank to follow the selected quality preset.",
                value: viewModel.bandwidthCapSummary
            )

            SettingsInputField(
                text: $viewModel.customBitrateMbpsText,
                placeholder: "Optional custom cap in Mbps"
            )
            .keyboardType(.decimalPad)

            Text(viewModel.customBitrateFieldHint)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(
                    !viewModel.hasInvalidCustomBitrateInput
                        ? .white.opacity(0.48)
                        : Color(red: 1.0, green: 0.55, blue: 0.52)
                )
        }
    }

    private var notificationsCard: some View {
        SettingsSectionCard(
            title: "Notifications",
            subtitle: "Useful alerts only for shows you already follow."
        ) {
            SettingsToggleRow(
                title: "New Episode Alerts",
                subtitle: "Get notified when Jellyfin exposes a new next-up episode for a series you already started watching.",
                isOn: Binding(
                    get: { viewModel.episodeReleaseNotificationsEnabled },
                    set: { newValue in
                        viewModel.episodeReleaseNotificationsEnabled = newValue
                        Task {
                            await viewModel.setEpisodeReleaseNotificationsEnabled(newValue)
                        }
                    }
                )
            )
        }
    }

    private var serverCard: some View {
        SettingsSectionCard(
            title: "Server",
            subtitle: "Manage the Jellyfin address ReelFin uses for your session."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsInputField(
                    text: $viewModel.serverURLText,
                    placeholder: "https://your-jellyfin-server"
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textContentType(.URL)
                .onChange(of: viewModel.serverURLText) { _, _ in
                    viewModel.serverURLDidChange()
                }

                if viewModel.hasPendingServerChange {
                    Text("Changing the server will ask you to sign in again before your library can sync.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                } else {
                    Text("The current address remains active until you save.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
        }
    }

    private var advancedPlaybackCard: some View {
        SettingsSectionCard(
            title: "Advanced Playback",
            subtitle: "Real engine controls for difficult files, Dolby Vision handling, and diagnostics."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSubsectionHeader(
                    title: "Engine",
                    subtitle: "These toggles apply immediately to future sessions."
                )

                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Use Local Playback Bridge",
                        subtitle: "Let ReelFin build a local synthetic HLS stream for difficult MKV / Dolby Vision paths when it improves compatibility.",
                        isOn: Binding(
                            get: { viewModel.localPlaybackBridgeEnabled },
                            set: { viewModel.setLocalPlaybackBridgeEnabled($0) }
                        )
                    )

                    SettingsRowDivider()

                    SettingsToggleRow(
                        title: "Faster Video-Only Startup",
                        subtitle: "Start with a lighter video-only bootstrap path before the full audio path is ready.",
                        isOn: Binding(
                            get: { viewModel.fasterVideoOnlyStartupEnabled },
                            set: { viewModel.setFasterVideoOnlyStartupEnabled($0) }
                        )
                    )

                    SettingsRowDivider()

                    Menu {
                        ForEach(DolbyVisionPackagingMode.allCases, id: \.self) { mode in
                            Button {
                                viewModel.setDolbyVisionPackagingMode(mode)
                            } label: {
                                if mode == viewModel.dolbyVisionPackagingMode {
                                    Label(mode.settingsLabel, systemImage: "checkmark")
                                } else {
                                    Text(mode.settingsLabel)
                                }
                            }
                        }
                    } label: {
                        SettingsValueRow(
                            title: "Dolby Vision Handling",
                            subtitle: viewModel.dolbyVisionPackagingMode.settingsSubtitle,
                            value: viewModel.dolbyVisionPackagingMode.settingsLabel
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button("Reset Advanced Playback Defaults") {
                    viewModel.resetAdvancedPlaybackDefaults()
                }
                .buttonStyle(SettingsInlineButtonStyle(primary: false))

                SettingsSubsectionHeader(
                    title: "Diagnostics",
                    subtitle: "Probe a sample of library items through the playback planner to catch broken routes before you notice them."
                )

                VStack(spacing: 0) {
                    SettingsStepperRow(
                        title: "Loops",
                        subtitle: "How many times ReelFin should sample the home feed.",
                        value: $viewModel.diagnosticsLoopCount,
                        range: 1 ... 10
                    )

                    SettingsRowDivider()

                    SettingsStepperRow(
                        title: "Sample Size",
                        subtitle: "How many items to check per diagnostics loop.",
                        value: $viewModel.diagnosticsSampleSize,
                        range: 1 ... 30
                    )
                }

                Button {
                    Task {
                        await viewModel.runPlaybackDiagnostics()
                    }
                } label: {
                    HStack {
                        if viewModel.isRunningDiagnostics {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.black)
                        }
                        Text(viewModel.isRunningDiagnostics ? "Running Diagnostics..." : "Run Playback Diagnostics")
                    }
                }
                .buttonStyle(SettingsInlineButtonStyle(primary: true))
                .disabled(viewModel.isRunningDiagnostics)

                if let report = viewModel.diagnosticsReport, !report.isEmpty {
                    DiagnosticsReportView(report: report)
                }
            }
        }
    }

    private var aboutCard: some View {
        SettingsSectionCard(
            title: "About",
            subtitle: "Support links and build information."
        ) {
            VStack(spacing: 0) {
                SettingsInfoRow(title: "Version", value: appVersionLabel)

                if metadata.hasSupportSurface {
                    if metadata.privacyPolicyURL != nil ||
                        metadata.termsOfServiceURL != nil ||
                        metadata.supportURL != nil ||
                        metadata.supportEmailURL != nil {
                        SettingsRowDivider()
                    }

                    VStack(spacing: 0) {
                        if let privacyPolicyURL = metadata.privacyPolicyURL {
                            SettingsLinkRow(title: "Privacy Policy") {
                                openURL(privacyPolicyURL)
                            }
                        }

                        if let termsOfServiceURL = metadata.termsOfServiceURL {
                            SettingsRowDivider()
                            SettingsLinkRow(title: "Terms of Service") {
                                openURL(termsOfServiceURL)
                            }
                        }

                        if let supportURL = metadata.supportURL {
                            SettingsRowDivider()
                            SettingsLinkRow(title: "Support") {
                                openURL(supportURL)
                            }
                        }

                        if let supportEmailURL = metadata.supportEmailURL {
                            SettingsRowDivider()
                            SettingsLinkRow(title: "Email Support") {
                                openURL(supportEmailURL)
                            }
                        }
                    }
                }
            }
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            onLogout()
        } label: {
            Text("Sign Out")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SettingsInlineButtonStyle(primary: false, destructive: true))
    }

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                Text(
                    viewModel.hasPendingChanges
                        ? "Playback and server changes are ready to apply."
                        : "Home, notifications, and advanced engine settings apply immediately. Playback and server settings are up to date."
                )
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Button("Test Connection") {
                            runConnectionTest()
                        }
                        .buttonStyle(SettingsInlineButtonStyle(primary: false))

                        Button(viewModel.saveButtonTitle) {
                            persistSettings()
                        }
                        .buttonStyle(SettingsInlineButtonStyle(primary: true))
                        .disabled(!viewModel.canSave || !viewModel.hasPendingChanges)
                    }

                    VStack(spacing: 12) {
                        Button("Test Connection") {
                            runConnectionTest()
                        }
                        .buttonStyle(SettingsInlineButtonStyle(primary: false))

                        Button(viewModel.saveButtonTitle) {
                            persistSettings()
                        }
                        .buttonStyle(SettingsInlineButtonStyle(primary: true))
                        .disabled(!viewModel.canSave || !viewModel.hasPendingChanges)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
    }
    #endif

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return 32
        #else
        return horizontalSizeClass == .compact ? 20 : 28
        #endif
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version
    }

    private func persistSettings() {
        Task {
            let result = await viewModel.save()
            if result == .requiresReauthentication {
                onLogout()
            }
        }
    }

    private func runConnectionTest() {
        Task {
            await viewModel.testConnection()
        }
    }

    @ViewBuilder
    private func languagePreferenceMenu(
        title: String,
        subtitle: String,
        selection: Binding<String>
    ) -> some View {
        Menu {
            ForEach(SettingsLanguageOption.curatedOptions) { option in
                Button {
                    selection.wrappedValue = option.code ?? ""
                } label: {
                    if option.code == normalizedLanguageSelection(selection.wrappedValue) {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            SettingsValueRow(
                title: title,
                subtitle: subtitle,
                value: SettingsLanguageOption.label(for: selection.wrappedValue)
            )
        }
        .buttonStyle(.plain)
    }

    private func normalizedLanguageSelection(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    #if os(tvOS)
    private func tvSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func tvInfoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func tvMenuRow<MenuContent: View>(
        title: String,
        value: String,
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        Menu {
            menuContent()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .buttonStyle(.plain)
    }

    private func legacySupportLinkButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    #endif
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.065),
                            Color.white.opacity(0.028)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 14)
    }
}

private struct SettingsSubsectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsMiniStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct HomeSectionPreferenceRow: View {
    let kind: HomeSectionKind
    let isVisible: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onVisibilityChange: (Bool) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                Image(systemName: kind.settingsIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.settingsTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(kind.settingsSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { isVisible },
                set: onVisibilityChange
            ))
            .labelsHidden()
            .tint(.white)

            HStack(spacing: 8) {
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(SettingsIconButtonStyle())
                .disabled(!canMoveUp)

                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(SettingsIconButtonStyle())
                .disabled(!canMoveDown)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.white)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.trailing)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }
}

private struct SettingsInputField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

#if !os(tvOS)
private struct SettingsStepperRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text("\(value)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .tint(.white)
    }
}

private struct DiagnosticsReportView: View {
    let report: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest Report")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(report)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
        }
    }
}
#endif

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
            }
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

private struct SettingsStatusBanner: View {
    enum Tone {
        case success
        case error
    }

    let text: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tone == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var iconColor: Color {
        switch tone {
        case .success:
            return Color(red: 0.42, green: 0.92, blue: 0.65)
        case .error:
            return Color(red: 1.0, green: 0.53, blue: 0.50)
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .success:
            return Color(red: 0.09, green: 0.18, blue: 0.13)
        case .error:
            return Color(red: 0.21, green: 0.10, blue: 0.11)
        }
    }

    private var borderColor: Color {
        iconColor.opacity(0.22)
    }
}

private struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.72 : 0.9))
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct SettingsInlineButtonStyle: ButtonStyle {
    let primary: Bool
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(foregroundColor.opacity(configuration.isPressed ? 0.82 : 1))
            .background(backgroundFill.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private var foregroundColor: Color {
        if primary { return .black }
        if destructive { return Color(red: 1.0, green: 0.48, blue: 0.48) }
        return .white
    }

    private var backgroundFill: Color {
        if primary { return .white }
        if destructive { return Color(red: 0.22, green: 0.10, blue: 0.11) }
        return Color.white.opacity(0.05)
    }

    private var borderColor: Color {
        if primary { return Color.white.opacity(0.16) }
        if destructive { return Color.red.opacity(0.22) }
        return Color.white.opacity(0.08)
    }
}

private struct SettingsActionButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(
                Group {
                    if primary {
                        LinearGradient(
                            colors: [ReelFinTheme.accent, ReelFinTheme.accentSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        ReelFinTheme.card.opacity(0.92)
                    }
                }
                .opacity(configuration.isPressed ? 0.75 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension QualityPreference {
    var settingsLabel: String {
        switch self {
        case .auto:
            return "Auto"
        case .p1080:
            return "1080p"
        case .p720:
            return "720p"
        case .p480:
            return "480p"
        }
    }
}

private extension PlaybackStrategy {
    var settingsLabel: String {
        switch self {
        case .bestQualityFastest:
            return "Smart Auto"
        case .directRemuxOnly:
            return "Direct / Remux Only"
        }
    }
}

private extension PlaybackPolicy {
    var settingsLabel: String {
        switch self {
        case .auto:
            return "Standard"
        case .originalFirst:
            return "Prefer Original"
        case .originalLockHDRDV:
            return "Preserve HDR"
        }
    }
}

private extension DolbyVisionPackagingMode {
    var settingsLabel: String {
        switch self {
        case .dvProfile81Compatible:
            return "Compatible"
        case .hdr10OnlyFallback:
            return "HDR10 Fallback"
        case .primaryDolbyVisionExperimental:
            return "Experimental DV-First"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .dvProfile81Compatible:
            return "Default Apple-friendly packaging that keeps Dolby Vision best effort with an HDR10 floor."
        case .hdr10OnlyFallback:
            return "Strip Dolby Vision signaling and force a safer HDR10 path."
        case .primaryDolbyVisionExperimental:
            return "Strict Dolby Vision signaling with lower compatibility on mixed device/server setups."
        }
    }
}

private extension HomeSectionKind {
    var settingsTitle: String {
        switch self {
        case .continueWatching:
            return "Continue Watching"
        case .recentlyReleasedMovies:
            return "Recently Released Movies"
        case .recentlyReleasedSeries:
            return "Recently Released TV Shows"
        case .nextUp:
            return "Next Up"
        case .recentlyAddedMovies:
            return "Recently Added Movies"
        case .recentlyAddedSeries:
            return "Recently Added TV"
        case .popular:
            return "Popular"
        case .trending:
            return "Trending"
        case .movies:
            return "Movies"
        case .shows:
            return "Shows"
        case .latest:
            return "Latest"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .continueWatching:
            return "Resume titles already in progress."
        case .recentlyReleasedMovies:
            return "Fresh movie releases from your server."
        case .recentlyReleasedSeries:
            return "Newly released series worth checking first."
        case .nextUp:
            return "Jump straight into the next episode."
        case .recentlyAddedMovies:
            return "The newest movie arrivals in your library."
        case .recentlyAddedSeries:
            return "Recently added shows and seasons."
        case .popular:
            return "Popular items from your server."
        case .trending:
            return "Trending items right now."
        case .movies:
            return "General movie browsing rail."
        case .shows:
            return "General TV show browsing rail."
        case .latest:
            return "Latest items across the library."
        }
    }

    var settingsIcon: String {
        switch self {
        case .continueWatching:
            return "play.circle.fill"
        case .recentlyReleasedMovies:
            return "film.stack.fill"
        case .recentlyReleasedSeries:
            return "sparkles.tv.fill"
        case .nextUp:
            return "forward.end.fill"
        case .recentlyAddedMovies:
            return "film.fill"
        case .recentlyAddedSeries:
            return "tv.fill"
        case .popular:
            return "flame.fill"
        case .trending:
            return "chart.line.uptrend.xyaxis"
        case .movies:
            return "popcorn.fill"
        case .shows:
            return "tv"
        case .latest:
            return "clock.fill"
        }
    }
}

private struct SettingsLanguageOption: Identifiable {
    let code: String?
    let label: String

    var id: String {
        code ?? "automatic"
    }

    static var curatedOptions: [SettingsLanguageOption] {
        [nil, "fr", "en", "es", "de", "it", "pt", "ja", "ko", "zh"].map { code in
            SettingsLanguageOption(code: code, label: displayLabel(for: code))
        }
    }

    static func label(for code: String) -> String {
        displayLabel(for: normalized(code))
    }

    private static func displayLabel(for code: String?) -> String {
        guard let code else { return "Automatic" }
        let normalized = normalized(code) ?? code
        if let localized = Locale.current.localizedString(forLanguageCode: normalized) {
            return localized.capitalized
        }
        return normalized.uppercased()
    }

    private static func normalized(_ code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(2))
    }
}

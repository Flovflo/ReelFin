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
            ReelFinTheme.pageGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Server Settings")
                        .reelFinTitleStyle()

                    TextField("Server URL", text: $viewModel.serverURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(ReelFinTheme.card.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)

                    Toggle(isOn: $viewModel.allowCellularStreaming) {
                        Text("Allow Cellular Streaming")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(14)
                    .background(ReelFinTheme.card.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preferred Quality")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Picker("Preferred Quality", selection: $viewModel.preferredQuality) {
                            ForEach(QualityPreference.allCases, id: \.self) { quality in
                                Text(quality.settingsLabel).tag(quality)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(14)
                    .background(ReelFinTheme.card.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Playback")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Toggle(isOn: $viewModel.forceH264FallbackWhenNotDirectPlay) {
                            Text("Force H264 if not Direct Play")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        Toggle(isOn: $viewModel.nerdOverlayEnabled) {
                            Text("Nerd debug overlay")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .onChange(of: viewModel.nerdOverlayEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "reelfin.playback.debugOverlay.enabled")
                        }
                    }
                    .padding(14)
                    .background(ReelFinTheme.card.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let info = viewModel.infoMessage {
                        Text(info)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.green)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.red)
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
                        .disabled(!viewModel.canSave)
                    }

                    Button("Sign Out") {
                        onLogout()
                    }
                    .buttonStyle(SettingsActionButtonStyle(primary: false))

                    if metadata.hasSupportSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Legal & Support")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)

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

                            if let supportEmailURL = metadata.supportEmailURL, let supportEmail = metadata.supportEmail {
                                legacySupportLinkButton(title: "Email Support", subtitle: supportEmail) {
                                    openURL(supportEmailURL)
                                }
                            }
                        }
                        .padding(14)
                        .background(ReelFinTheme.card.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    #endif

    #if !os(tvOS)
    private var iosBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerBlock

                    if viewModel.errorMessage != nil || viewModel.infoMessage != nil {
                        statusBanner
                    }

                    accountCard
                    playbackCard
                    serverCard
                    aboutCard
                    signOutButton
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Only the settings that actually change the app.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
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
            subtitle: "The connection you are currently using."
        ) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.displayUsername)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(viewModel.displayServerHost)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                SettingsTag(text: "Connected")
            }
        }
    }

    private var playbackCard: some View {
        SettingsSectionCard(
            title: "Playback",
            subtitle: "Only preferences that directly change playback behavior."
        ) {
            VStack(spacing: 0) {
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
                        subtitle: "Choose how aggressive video streaming should be.",
                        value: viewModel.preferredQuality.settingsLabel
                    )
                }
                .buttonStyle(.plain)

                SettingsRowDivider()

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
                        subtitle: "Balance reliable playback against original HDR quality.",
                        value: viewModel.playbackPolicy.settingsLabel
                    )
                }
                .buttonStyle(.plain)

                SettingsRowDivider()

                languagePreferenceMenu(
                    title: "Preferred Audio",
                    subtitle: "Start with this audio language when it is available.",
                    selection: $viewModel.preferredAudioLanguage
                )

                SettingsRowDivider()

                languagePreferenceMenu(
                    title: "Forced Subtitles",
                    subtitle: "Pick which forced subtitle track opens automatically.",
                    selection: $viewModel.preferredSubtitleLanguage
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    title: "Compatibility Mode",
                    subtitle: "Use H.264 fallback when some titles fail to start cleanly.",
                    isOn: $viewModel.forceH264FallbackWhenNotDirectPlay
                )
            }
        }
    }

    private var serverCard: some View {
        SettingsSectionCard(
            title: "Server",
            subtitle: "Update the Jellyfin address or verify that it is reachable."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                TextField("https://your-jellyfin-server", text: $viewModel.serverURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .onChange(of: viewModel.serverURLText) { _, _ in
                        viewModel.serverURLDidChange()
                    }

                if viewModel.hasPendingServerChange {
                    Text("Changing the server will ask you to sign in again.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                }

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
                        .disabled(!viewModel.canSave)
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
                        .disabled(!viewModel.canSave)
                    }
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.54))
                }
            }

            content
        }
        .padding(18)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
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

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.44))
            }
        }
    }
}

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
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
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

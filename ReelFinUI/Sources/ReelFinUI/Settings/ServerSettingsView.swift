import PlaybackEngine
import Shared
import SwiftUI

struct ServerSettingsView: View {
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

                        Toggle(
                            isOn: Binding(
                                get: { viewModel.nativePlayerEnabled },
                                set: { viewModel.setNativePlayerEnabled($0) }
                            )
                        ) {
                            Text("Use native local player")
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
    private static let reelTranscodeRepositoryURL = URL(string: "https://github.com/Flovflo/ReelTranscode")!

    private var iosBody: some View {
        Form {
            iosStatusSection

            Section {
                LabeledContent("User", value: viewModel.displayUsername)
                LabeledContent("Status", value: viewModel.connectionStatusLabel)

                Button(role: .destructive) {
                    onLogout()
                } label: {
                    Label("Change Account", systemImage: "person.crop.circle.badge.xmark")
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Signs out on this device so you can connect with another Jellyfin account.")
            }

            Section {
                LabeledContent("Current Address") {
                    Text(currentServerAddress)
                        .multilineTextAlignment(.trailing)
                }

                TextField("Server URL", text: $viewModel.serverURLText, prompt: Text("https://your-jellyfin-server"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textContentType(.URL)
                    .accessibilityIdentifier("settings_server_url_field")
                    .onChange(of: viewModel.serverURLText) { _, _ in
                        viewModel.serverURLDidChange()
                    }

                Button {
                    runConnectionTest()
                } label: {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                }

                Button {
                    persistSettings()
                } label: {
                    Label(serverSaveTitle, systemImage: "checkmark.circle")
                }
                .disabled(!viewModel.canSave || !viewModel.hasPendingServerChange)
            } header: {
                Text("Server")
            } footer: {
                Text(serverFooterText)
            }

            Section {
                Toggle(
                    isOn: Binding(
                        get: { viewModel.nativePlayerEnabled },
                        set: { viewModel.setNativePlayerEnabled($0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Native Local Player")
                        Text("Experimental original-file path. Server transcoding is blocked while this is on.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $viewModel.forceH264FallbackWhenNotDirectPlay) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("H.264 Compatibility Fallback")
                        Text("Only applies to the legacy player path.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(viewModel.nativePlayerEnabled)

                Button {
                    persistSettings()
                } label: {
                    Label(viewModel.saveButtonTitle, systemImage: "checkmark.circle")
                }
                .disabled(!viewModel.canSave || !viewModel.hasPendingChanges)
            } header: {
                Text("Playback")
            } footer: {
                Text("Native mode asks Jellyfin for the original file and refuses HLS transcode URLs.")
            }

            Section {
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text("New Episode Alerts")
                        Text("Get notified when Jellyfin exposes a new next-up episode for a show you follow.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Notifications")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to use ReelTranscode")
                    Text("A setup guide is coming soon. The project is already available on GitHub.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Link(destination: Self.reelTranscodeRepositoryURL) {
                    Label("Open ReelTranscode on GitHub", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("ReelTranscode")
            }

            Section {
                LabeledContent("Version", value: appVersionLabel)
                supportLinks
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("settings_screen")
        .task {
            await viewModel.refreshEpisodeReleaseNotificationsState()
        }
    }

    @ViewBuilder
    private var iosStatusSection: some View {
        if let error = viewModel.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } else if let info = viewModel.infoMessage {
            Section {
                Label(info, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var supportLinks: some View {
        if let privacyPolicyURL = metadata.privacyPolicyURL {
            Link("Privacy Policy", destination: privacyPolicyURL)
        }

        if let termsOfServiceURL = metadata.termsOfServiceURL {
            Link("Terms of Service", destination: termsOfServiceURL)
        }

        if let supportURL = metadata.supportURL {
            Link("Support", destination: supportURL)
        }

        if let supportEmailURL = metadata.supportEmailURL {
            Link("Email Support", destination: supportEmailURL)
        }
    }

    private var currentServerAddress: String {
        let trimmed = viewModel.serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No server configured" : trimmed
    }

    private var serverSaveTitle: String {
        viewModel.hasPendingServerChange ? "Save Server" : "Server Saved"
    }

    private var serverFooterText: String {
        if viewModel.hasPendingServerChange {
            return "Changing the server signs you out so you can authenticate again."
        }

        return "Use the connection test when the server feels unreachable."
    }
    #endif

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

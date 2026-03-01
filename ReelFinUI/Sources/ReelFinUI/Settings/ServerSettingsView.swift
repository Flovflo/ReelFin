import Shared
import SwiftUI

struct ServerSettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: ServerSettingsViewModel
    let onLogout: () -> Void

    init(dependencies: ReelFinDependencies, onLogout: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ServerSettingsViewModel(dependencies: dependencies))
        self.onLogout = onLogout
    }

    var body: some View {
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

                    TextField("User", text: $viewModel.username)
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
                            Text("Auto").tag(QualityPreference.auto)
                            Text("1080p").tag(QualityPreference.p1080)
                            Text("720p").tag(QualityPreference.p720)
                            Text("480p").tag(QualityPreference.p480)
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
                            Task {
                                await viewModel.testConnection()
                            }
                        }
                        .buttonStyle(SettingsActionButtonStyle(primary: false))

                        Button("Save") {
                            Task {
                                await viewModel.save()
                            }
                        }
                        .buttonStyle(SettingsActionButtonStyle(primary: true))
                    }

                    Button("Sign Out") {
                        onLogout()
                    }
                    .buttonStyle(SettingsActionButtonStyle(primary: false))
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 14 : 22
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

#if os(iOS)
import Shared
import SwiftUI

struct ConnectionLandingShowcaseView: View {
    let compact: Bool
    let imagePipeline: any ImagePipelineProtocol
    @Binding var serverURLText: String
    let focusedField: FocusState<LoginFocusField?>.Binding
    let hasSavedServer: Bool
    let isTestingConnection: Bool
    let serverMessage: String?
    let serverErrorMessage: String?
    let canContinue: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: compact ? 24 : 30) {
            Spacer(minLength: compact ? 10 : 24)

            RollingPosterCarousel(
                posters: ReelFinShowcaseContent.posters,
                compact: compact,
                accent: ReelFinShowcaseContent.accent,
                glow: ReelFinShowcaseContent.glow,
                imagePipeline: imagePipeline
            )
            .frame(height: compact ? 340 : 390)

            GlassPanel(cornerRadius: compact ? 30 : 34, tint: OnboardingPalette.panelTint, padding: compact ? 24 : 28) {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingEyebrowChip(title: "REELFIN", tint: ReelFinShowcaseContent.accent)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connect to Jellyfin")
                            .font(.system(size: compact ? 30 : 36, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(OnboardingPalette.primaryText)

                        Text("Add your server and let ReelFin handle the rest with a more native playback experience.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(OnboardingPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if hasSavedServer {
                        StageFeedbackChip(text: "Saved server ready", tint: OnboardingPalette.glowWhite)
                    }

                    TextField("https://server.example.com", text: $serverURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .textContentType(.URL)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.primaryText)
                        .focused(focusedField, equals: .serverURL)
                        .submitLabel(.continue)
                        .onSubmit(onContinue)
                        .accessibilityIdentifier("login_server_field")
                        .onboardingFieldSurface()

                    if isTestingConnection {
                        StageFeedbackChip(text: "Checking server", tint: OnboardingPalette.secondaryText)
                    } else if let serverErrorMessage {
                        StageFeedbackChip(text: serverErrorMessage, tint: Color.red.opacity(0.92))
                    } else if let serverMessage {
                        StageFeedbackChip(text: serverMessage, tint: OnboardingPalette.secondaryText)
                    }

                    PremiumCTAButton(
                        title: "Continue",
                        isLoading: isTestingConnection,
                        isEnabled: canContinue,
                        action: onContinue
                    )
                    .accessibilityIdentifier("login_server_continue")
                }
            }
            .frame(maxWidth: compact ? 430 : 520)

            Spacer(minLength: compact ? 24 : 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, compact ? 16 : 24)
    }
}
#endif

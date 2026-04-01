#if os(iOS)
import SwiftUI

struct ConnectionLandingView: View {
    let compact: Bool
    let titleSize: CGFloat
    let bodySize: CGFloat
    @Binding var serverURLText: String
    let focusedField: FocusState<LoginFocusField?>.Binding
    let hasSavedServer: Bool
    let isTestingConnection: Bool
    let serverMessage: String?
    let serverErrorMessage: String?
    let canContinue: Bool
    let onContinue: () -> Void

    var body: some View {
        GlassPanel(cornerRadius: compact ? 30 : 34, padding: compact ? 24 : 28) {
            VStack(alignment: .leading, spacing: compact ? 20 : 24) {
                StageHeader(
                    title: "Connect to Jellyfin",
                    subtitle: "Fast, fluid, and built for Apple from first tap to first frame.",
                    titleSize: titleSize,
                    bodySize: bodySize
                )

                VStack(alignment: .leading, spacing: 14) {
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
                        isEnabled: canContinue && !isTestingConnection,
                        action: onContinue
                    )
                    .accessibilityIdentifier("login_server_continue")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif

#if os(iOS)
import Shared
import SwiftUI

enum LoginFocusField {
    case serverURL
    case username
    case password
}

struct ServerEntryStageView: View {
    @Binding var serverURLText: String
    let focusedField: FocusState<LoginFocusField?>.Binding
    let hasSavedServer: Bool
    let isTestingConnection: Bool
    let serverMessage: String?
    let serverErrorMessage: String?
    let canContinue: Bool
    let titleSize: CGFloat
    let bodySize: CGFloat
    let onContinue: () -> Void

    var body: some View {
        GlassPanel(cornerRadius: 34, tint: OnboardingPalette.panelTint, padding: 28) {
            VStack(alignment: .leading, spacing: 20) {
                StageHeader(
                    title: "Add your Jellyfin server",
                    subtitle: "Enter the address you already use. ReelFin checks it before loading your library.",
                    titleSize: titleSize,
                    bodySize: bodySize
                )

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
    }
}

struct CredentialsStageView: View {
    @Binding var username: String
    @Binding var password: String
    let focusedField: FocusState<LoginFocusField?>.Binding
    let serverHost: String
    let isSubmitting: Bool
    let authErrorMessage: String?
    let canSubmit: Bool
    let titleSize: CGFloat
    let bodySize: CGFloat
    let onSubmit: () -> Void

    var body: some View {
        GlassPanel(cornerRadius: 34, tint: OnboardingPalette.panelTint, padding: 28) {
            VStack(alignment: .leading, spacing: 20) {
                StageHeader(
                    title: "Sign in",
                    subtitle: "Use the account you already use on \(serverHost).",
                    titleSize: titleSize,
                    bodySize: bodySize
                )

                VStack(spacing: 12) {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.username)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.primaryText)
                        .focused(focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField.wrappedValue = .password
                        }
                        .accessibilityIdentifier("login_username_field")
                        .onboardingFieldSurface()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.primaryText)
                        .focused(focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(onSubmit)
                        .accessibilityIdentifier("login_password_field")
                        .onboardingFieldSurface()
                }
                .accessibilityIdentifier("login_credentials_sheet")

                if isSubmitting {
                    StageFeedbackChip(text: "Signing in", tint: OnboardingPalette.secondaryText)
                } else if let authErrorMessage {
                    StageFeedbackChip(text: authErrorMessage, tint: Color.red.opacity(0.92))
                }

                PremiumCTAButton(
                    title: "Sign in",
                    isLoading: isSubmitting,
                    isEnabled: canSubmit,
                    action: onSubmit
                )
                .accessibilityIdentifier("login_sign_in")
            }
        }
    }
}

struct SuccessStageView: View {
    let titleSize: CGFloat
    let bodySize: CGFloat

    var body: some View {
        GlassPanel(cornerRadius: 34, tint: OnboardingPalette.mint.opacity(0.08), padding: 32) {
            VStack(alignment: .center, spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(OnboardingPalette.primaryText)

                Text("Library connected")
                    .font(.system(size: titleSize - 2, weight: .bold))
                    .foregroundStyle(OnboardingPalette.primaryText)
                    .accessibilityIdentifier("login_success_title")

                Text("Your Apple-first setup is ready.")
                    .font(.system(size: bodySize, weight: .medium))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct StageHeader: View {
    let title: String
    let subtitle: String
    let titleSize: CGFloat
    let bodySize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(OnboardingPalette.primaryText)

            Text(subtitle)
                .font(.system(size: bodySize, weight: .medium))
                .foregroundStyle(OnboardingPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StageFeedbackChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular, in: .capsule)
                } else {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func onboardingFieldSurface() -> some View {
        self
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}
#endif

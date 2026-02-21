import SwiftUI
import Shared
import UIKit

struct LoginView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: LoginViewModel
    private let onLogin: (UserSession) -> Void

    init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(dependencies: dependencies))
        self.onLogin = onLogin
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(for: proxy.size)
            let contentHeight = proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
            let compactFormFillHeight = max(
                metrics.formMinHeight,
                contentHeight - metrics.topPadding - metrics.bottomPadding - metrics.heroHeight + metrics.overlap
            )
            ZStack {
                // Background expands edge-to-edge under notch/home indicator.
                ReelFinTheme.pageGradient.ignoresSafeArea()

                VStack(spacing: -metrics.overlap) {
                    heroPanel(height: metrics.heroHeight, cornerRadius: metrics.cornerRadius)
                    formPanel(metrics: metrics)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: metrics.isCompact ? compactFormFillHeight : metrics.formMinHeight,
                            alignment: .top
                        )
                }
                .frame(maxWidth: metrics.cardMaxWidth)
                .padding(.horizontal, metrics.outerHorizontalPadding)
                .padding(.top, proxy.safeAreaInsets.top + metrics.topPadding)
                .padding(.bottom, proxy.safeAreaInsets.bottom + metrics.bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // Force the root container to match the full device bounds.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func formPanel(metrics: LoginLayoutMetrics) -> some View {
        VStack(spacing: 14) {
            textField("Server URL", text: $viewModel.serverURLText, keyboardType: .URL)
                .textContentType(.URL)
            textField("Username", text: $viewModel.username, keyboardType: .default)
                .textContentType(.username)

            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(ReelFinTheme.card.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let infoMessage = viewModel.infoMessage {
                Text(infoMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.testConnection() }
                } label: {
                    Label(viewModel.isTestingConnection ? "Testing..." : "Test Connection", systemImage: "network")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(viewModel.isTestingConnection)

                Button {
                    Task {
                        if let session = await viewModel.login() {
                            onLogin(session)
                        }
                    }
                } label: {
                    Label(viewModel.isLoading ? "Signing in..." : "Sign In", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(viewModel.isLoading)
            }
        }
        .padding(.horizontal, metrics.formHorizontalPadding)
        .padding(.top, metrics.formTopPadding)
        .padding(.bottom, metrics.formBottomPadding)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(ReelFinTheme.surface.opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                        .stroke(ReelFinTheme.panelStroke, lineWidth: 1)
                }
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.03), lineWidth: 1)
        }
    }

    private func heroPanel(height: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.18, blue: 0.28),
                    Color(red: 0.07, green: 0.11, blue: 0.18),
                    Color(red: 0.03, green: 0.04, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .blur(radius: 10)
                    .offset(x: 30, y: -70)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome back")
                    .reelFinTitleStyle()
                Text("Connect to your Jellyfin server")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func textField(_ title: String, text: Binding<String>, keyboardType: UIKeyboardType) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .keyboardType(keyboardType)
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(ReelFinTheme.card.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
    }

    private func layoutMetrics(for size: CGSize) -> LoginLayoutMetrics {
        let compact = size.width < 700 || horizontalSizeClass != .regular

        if compact {
            return LoginLayoutMetrics(
                isCompact: true,
                cardMaxWidth: min(size.width - 24, 560),
                outerHorizontalPadding: 12,
                heroHeight: min(max(186, size.height * 0.25), 248),
                overlap: 20,
                cornerRadius: 28,
                formHorizontalPadding: 16,
                formTopPadding: 26,
                formBottomPadding: 24,
                topPadding: 8,
                bottomPadding: 10,
                formMinHeight: 380
            )
        }

        return LoginLayoutMetrics(
            isCompact: false,
            cardMaxWidth: min(size.width - 40, 900),
            outerHorizontalPadding: 20,
            heroHeight: min(max(220, size.height * 0.28), 320),
            overlap: 24,
            cornerRadius: 34,
            formHorizontalPadding: 24,
            formTopPadding: 34,
            formBottomPadding: 28,
            topPadding: 18,
            bottomPadding: 18,
            formMinHeight: 420
        )
    }
}

private struct LoginLayoutMetrics {
    let isCompact: Bool
    let cardMaxWidth: CGFloat
    let outerHorizontalPadding: CGFloat
    let heroHeight: CGFloat
    let overlap: CGFloat
    let cornerRadius: CGFloat
    let formHorizontalPadding: CGFloat
    let formTopPadding: CGFloat
    let formBottomPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let formMinHeight: CGFloat
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [ReelFinTheme.accent, ReelFinTheme.accentSecondary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(ReelFinTheme.card.opacity(configuration.isPressed ? 0.7 : 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

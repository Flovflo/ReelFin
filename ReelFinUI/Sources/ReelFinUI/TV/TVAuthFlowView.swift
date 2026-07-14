#if os(tvOS)
import Shared
import SwiftUI

struct TVAuthFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: TVAuthScreen

    private let dependencies: ReelFinDependencies
    private let settingsStore: SettingsStoreProtocol
    private let onLogin: (UserSession) -> Void

    init(dependencies: ReelFinDependencies, onLogin: @escaping (UserSession) -> Void) {
        self.dependencies = dependencies
        settingsStore = dependencies.settingsStore
        self.onLogin = onLogin
        _screen = State(initialValue: Self.initialScreen(settingsStore: dependencies.settingsStore))
    }

    var body: some View {
        ZStack {
            switch screen {
            case .onboarding:
                TVOnboardingView(
                    initialIndex: TVAuthDebugOptions.onboardingPage,
                    onComplete: completeOnboarding
                )
                .transition(onboardingTransition)
            case .login:
                TVLoginView(dependencies: dependencies, onLogin: onLogin)
                    .transition(loginTransition)
            }
        }
        .animation(authAnimation, value: screen)
    }

    private func completeOnboarding() {
        settingsStore.hasCompletedOnboarding = true
        settingsStore.completedOnboardingVersion = ReelFinOnboardingVersion.current

        withAnimation(authAnimation) {
            screen = .login
        }
    }

    private var authAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.38, extraBounce: 0.02)
    }

    private var onboardingTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }

    private var loginTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.015))
    }

    private static func initialScreen(settingsStore: SettingsStoreProtocol) -> TVAuthScreen {
        if let debugScreen = TVAuthDebugOptions.screen {
            return debugScreen
        }

        if settingsStore.completedOnboardingVersion >= ReelFinOnboardingVersion.current {
            return .login
        }

        return .onboarding
    }
}

private enum TVAuthScreen {
    case onboarding
    case login
}

private enum TVAuthDebugOptions {
    static var screen: TVAuthScreen? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let flagIndex = arguments.firstIndex(of: "-reelfin-tv-auth-screen") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        switch arguments[valueIndex] {
        case "onboarding":
            return .onboarding
        case "login":
            return .login
        default:
            return nil
        }
    }

    static var onboardingPage: Int? {
        let arguments = ProcessInfo.processInfo.arguments

        guard let flagIndex = arguments.firstIndex(of: "-reelfin-tv-onboarding-page") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return Int(arguments[valueIndex])
    }
}

#Preview("TV Auth Flow") {
    TVAuthFlowView(dependencies: ReelFinPreviewFactory.dependencies(authenticated: false)) { _ in }
}
#endif

import Foundation
import Observation
import Shared
import SwiftUI

enum ReelFinOnboardingVersion {
    static let current = 4
}

@MainActor
@Observable
final class RootViewModel {
    var isAuthenticated = false
    var didBootstrap = false

    private let dependencies: ReelFinDependencies
    private var authenticationGeneration = 0

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
    }

    func runRootLifecycle() async {
        let invalidations = dependencies.apiClient.sessionInvalidations
        await bootstrap()

        for await _ in invalidations {
            guard !Task.isCancelled else { return }
            let generation = authenticationGeneration
            let session = await dependencies.apiClient.currentSession()
            guard !Task.isCancelled else { return }
            guard authenticationGeneration == generation, session == nil else { continue }
            authenticationGeneration &+= 1
            withAnimation(.easeInOut(duration: 0.2)) {
                didBootstrap = true
                isAuthenticated = false
            }
        }
    }

    func bootstrap() async {
        let session = await dependencies.apiClient.currentSession()
        let serverConfig = await dependencies.apiClient.currentConfiguration() ?? dependencies.settingsStore.serverConfiguration

        if session != nil && serverConfig != nil {
            markOnboardingCompletedIfNeeded()
            isAuthenticated = true
            didBootstrap = true
            return
        }

        guard dependencies.settingsStore.completedOnboardingVersion >= ReelFinOnboardingVersion.current else {
            isAuthenticated = false
            didBootstrap = true
            return
        }

        isAuthenticated = false
        didBootstrap = true
    }

    func completeLogin(_ session: UserSession) {
        authenticationGeneration &+= 1
        dependencies.settingsStore.lastSession = session
        markOnboardingCompletedIfNeeded()
        withAnimation(.easeInOut(duration: 0.2)) {
            didBootstrap = true
            isAuthenticated = true
        }
    }

    func signOut() {
        authenticationGeneration &+= 1
        let generation = authenticationGeneration
        Task {
            await dependencies.apiClient.signOut()
            await MainActor.run {
                guard self.authenticationGeneration == generation else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.didBootstrap = true
                    self.isAuthenticated = false
                }
            }
        }
    }

    private func markOnboardingCompletedIfNeeded() {
        guard dependencies.settingsStore.completedOnboardingVersion < ReelFinOnboardingVersion.current else {
            return
        }

        dependencies.settingsStore.hasCompletedOnboarding = true
        dependencies.settingsStore.completedOnboardingVersion = ReelFinOnboardingVersion.current
    }
}

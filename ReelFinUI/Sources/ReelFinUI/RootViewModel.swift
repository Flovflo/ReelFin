import Foundation
import Observation
import Shared
import SwiftUI

enum ReelFinOnboardingVersion {
    static let current = 3
}

@MainActor
@Observable
final class RootViewModel {
    var isAuthenticated = false
    var didBootstrap = false

    private let dependencies: ReelFinDependencies

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
    }

    func bootstrap() async {
        guard dependencies.settingsStore.completedOnboardingVersion >= ReelFinOnboardingVersion.current else {
            isAuthenticated = false
            didBootstrap = true
            return
        }

        let session = await dependencies.apiClient.currentSession() ?? dependencies.settingsStore.lastSession
        let serverConfig = await dependencies.apiClient.currentConfiguration() ?? dependencies.settingsStore.serverConfiguration
        isAuthenticated = session != nil && serverConfig != nil
        didBootstrap = true
    }

    func completeLogin(_ session: UserSession) {
        dependencies.settingsStore.lastSession = session
        withAnimation(.easeInOut(duration: 0.2)) {
            isAuthenticated = true
        }
    }

    func signOut() {
        Task {
            await dependencies.apiClient.signOut()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.isAuthenticated = false
                }
            }
        }
    }
}

import ReelFinUI
import Shared
import UIKit

enum AppBootstrap {
    @MainActor
    static func makeDependencies(metadata: AppMetadata) -> ReelFinDependencies {
        if metadata.isMockModeEnabled || metadata.isScreenshotModeEnabled {
            UIView.setAnimationsEnabled(!metadata.isScreenshotModeEnabled)
            let arguments = Set(ProcessInfo.processInfo.arguments)
            let shouldStartLoggedOut = arguments.contains(AppMetadata.mockLoggedOutArgument)
            return ReelFinPreviewFactory.appStoreDependencies(authenticated: !shouldStartLoggedOut)
        }

        let container = AppContainer()
        return container.makeDependencies()
    }
}

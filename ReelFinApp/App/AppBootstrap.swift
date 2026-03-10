import ReelFinUI
import Shared
#if os(iOS)
import UIKit
#endif

enum AppBootstrap {
    @MainActor
    static func makeDependencies(metadata: AppMetadata) -> ReelFinDependencies {
        if metadata.isMockModeEnabled || metadata.isScreenshotModeEnabled {
#if os(iOS)
            UIView.setAnimationsEnabled(!metadata.isScreenshotModeEnabled)
#endif
            let arguments = Set(ProcessInfo.processInfo.arguments)
            let shouldStartLoggedOut = arguments.contains(AppMetadata.mockLoggedOutArgument)
            return ReelFinPreviewFactory.appStoreDependencies(authenticated: !shouldStartLoggedOut)
        }

        let container = AppContainer()
        return container.makeDependencies()
    }
}

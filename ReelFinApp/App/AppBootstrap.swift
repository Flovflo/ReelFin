import ReelFinUI
import Shared
import UIKit

enum AppBootstrap {
    @MainActor
    static func makeDependencies(metadata: AppMetadata) -> ReelFinDependencies {
        if metadata.isMockModeEnabled || metadata.isScreenshotModeEnabled {
            UIView.setAnimationsEnabled(!metadata.isScreenshotModeEnabled)
            return ReelFinPreviewFactory.appStoreDependencies()
        }

        let container = AppContainer()
        return container.makeDependencies()
    }
}

#if os(iOS)
import UIKit
import ReelFinUI

@MainActor
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationManager.shared.lock
    }
}
#endif

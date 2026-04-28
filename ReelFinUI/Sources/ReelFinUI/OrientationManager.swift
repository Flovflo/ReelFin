#if os(iOS)
import UIKit

@MainActor
public final class OrientationManager {
    public static let shared = OrientationManager()
    public var lock: UIInterfaceOrientationMask = .portrait
    var geometryUpdateHandler: ((UIInterfaceOrientationMask) -> Void)?

    private init() {}

    public func prepareLandscapeForPlayerCoverPresentation() {
        // Keep the current scene stable; PlayerView requests landscape after it is mounted.
    }

    public func lockLandscapeForPlayerPresentation(requestGeometryUpdate: Bool = true) {
        lock = .landscape
        updateSupportedOrientations()

        guard requestGeometryUpdate else { return }
        requestSceneGeometryUpdate(.landscapeRight)
    }

    public func restorePortraitAfterPlayerDismissal(requestGeometryUpdate: Bool = true) {
        lock = .portrait
        updateSupportedOrientations()

        guard requestGeometryUpdate else { return }
        requestSceneGeometryUpdate(.portrait)
    }

    private func requestSceneGeometryUpdate(_ orientation: UIInterfaceOrientationMask) {
        if let geometryUpdateHandler {
            geometryUpdateHandler(orientation)
            return
        }
        for windowScene in foregroundWindowScenes {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
    }

    private func updateSupportedOrientations() {
        for windowScene in foregroundWindowScenes {
            windowScene.windows.forEach { window in
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    private var foregroundWindowScenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { scene in
            guard let windowScene = scene as? UIWindowScene else { return nil }
            guard windowScene.activationState == .foregroundActive || windowScene.activationState == .foregroundInactive else {
                return nil
            }
            return windowScene
        }
    }
}
#endif

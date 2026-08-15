#if os(iOS)
import UIKit

@MainActor
public final class OrientationManager {
    public static let shared = OrientationManager()
    public var lock: UIInterfaceOrientationMask = .portrait
    var geometryUpdateHandler: ((UIInterfaceOrientationMask) -> Void)?
    var idiomProvider: () -> UIUserInterfaceIdiom = { UIDevice.current.userInterfaceIdiom }
    private var context: PlayerOrientationContext = .browsing

    private init() {}

    public func prepareLandscapeForPlayerCoverPresentation() {
        // Keep the current scene stable; PlayerView requests landscape after it is mounted.
    }

    public func supportedOrientations(for idiom: UIUserInterfaceIdiom) -> UIInterfaceOrientationMask {
        PlayerOrientationPolicy.supportedOrientations(idiom: idiom, context: context)
    }

    public func lockLandscapeForPlayerPresentation(requestGeometryUpdate: Bool = true) {
        let idiom = idiomProvider()
        let nextLock = PlayerOrientationPolicy.supportedOrientations(idiom: idiom, context: .player)
        guard context != .player || lock != nextLock else { return }
        context = .player
        lock = nextLock
        updateSupportedOrientations()

        guard requestGeometryUpdate else { return }
        guard let orientation = PlayerOrientationPolicy.requestedGeometryOrientation(idiom: idiom, context: .player) else {
            return
        }
        requestSceneGeometryUpdate(orientation)
    }

    public func restorePortraitAfterPlayerDismissal(requestGeometryUpdate: Bool = true) {
        let idiom = idiomProvider()
        context = .browsing
        lock = PlayerOrientationPolicy.supportedOrientations(idiom: idiom, context: .browsing)
        updateSupportedOrientations()

        guard requestGeometryUpdate else { return }
        guard let orientation = PlayerOrientationPolicy.requestedGeometryOrientation(idiom: idiom, context: .browsing) else {
            return
        }
        requestSceneGeometryUpdate(orientation)
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

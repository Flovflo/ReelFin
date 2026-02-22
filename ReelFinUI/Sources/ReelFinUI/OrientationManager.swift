import UIKit

@MainActor
public final class OrientationManager {
    public static let shared = OrientationManager()
    public var lock: UIInterfaceOrientationMask = .portrait

    private init() {}
}

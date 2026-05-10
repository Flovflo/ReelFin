#if targetEnvironment(macCatalyst)
import Foundation

enum MacRootCommandCenter {
    static let destinationUserInfoKey = "destination"

    static func select(_ destination: MacRootDestination) {
        NotificationCenter.default.post(
            name: .reelFinMacSelectDestination,
            object: nil,
            userInfo: [destinationUserInfoKey: destination.rawValue]
        )
    }

    static func refreshSelectedDestination() {
        NotificationCenter.default.post(name: .reelFinMacRefreshSelectedDestination, object: nil)
    }
}

extension Notification.Name {
    static let reelFinMacSelectDestination = Notification.Name("ReelFinMacSelectDestination")
    static let reelFinMacRefreshSelectedDestination = Notification.Name("ReelFinMacRefreshSelectedDestination")
}
#endif

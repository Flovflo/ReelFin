import SwiftUI

private struct TVTopNavigationFocusActionKey: EnvironmentKey {
    static let defaultValue: ((TVRootDestination) -> Void)? = nil
}

private struct TVTopNavigationVisibilityActionKey: EnvironmentKey {
    static let defaultValue: ((Bool) -> Void)? = nil
}

enum TVTopNavigationPlayerVisibilityPolicy {
    static func isVisible(hasActivePlayer: Bool) -> Bool {
        !hasActivePlayer
    }
}

extension EnvironmentValues {
    var tvTopNavigationFocusAction: ((TVRootDestination) -> Void)? {
        get { self[TVTopNavigationFocusActionKey.self] }
        set { self[TVTopNavigationFocusActionKey.self] = newValue }
    }

    /// Preferences emitted inside a `NavigationStack` destination do not reliably cross the
    /// destination boundary on tvOS. Player presentation therefore sends an explicit visibility
    /// veto to the root shell; this keeps global navigation out of every inline player path.
    var tvTopNavigationVisibilityAction: ((Bool) -> Void)? {
        get { self[TVTopNavigationVisibilityActionKey.self] }
        set { self[TVTopNavigationVisibilityActionKey.self] = newValue }
    }
}

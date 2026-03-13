import SwiftUI

private struct TVTopNavigationFocusActionKey: EnvironmentKey {
    static let defaultValue: ((TVRootDestination) -> Void)? = nil
}

extension EnvironmentValues {
    var tvTopNavigationFocusAction: ((TVRootDestination) -> Void)? {
        get { self[TVTopNavigationFocusActionKey.self] }
        set { self[TVTopNavigationFocusActionKey.self] = newValue }
    }
}

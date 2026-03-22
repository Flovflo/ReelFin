import SwiftUI

struct TVTopNavigationAppearancePreferenceKey: PreferenceKey {
    static var defaultValue = TVTopNavigationAppearance.neutral

    static func reduce(
        value: inout TVTopNavigationAppearance,
        nextValue: () -> TVTopNavigationAppearance
    ) {
        value = nextValue()
    }
}

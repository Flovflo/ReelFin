import Foundation
import SwiftUI

struct TVContentFocusRequest: Equatable {
    let destination: TVRootDestination
    let sequence: Int
}

typealias TVContentFocusReadyAction = (_ destination: TVRootDestination, _ sequence: Int) -> Void

private struct TVContentFocusReadyActionKey: EnvironmentKey {
    static let defaultValue: TVContentFocusReadyAction? = nil
}

extension EnvironmentValues {
    var tvContentFocusReadyAction: TVContentFocusReadyAction? {
        get { self[TVContentFocusReadyActionKey.self] }
        set { self[TVContentFocusReadyActionKey.self] = newValue }
    }
}

import Foundation
import os

public enum AppLog {
    public static let subsystem = "com.reelfin.app"
    public static let networking = Logger(subsystem: subsystem, category: "networking")
    public static let caching = Logger(subsystem: subsystem, category: "caching")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let playback = Logger(subsystem: subsystem, category: "playback")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}

public final class SignpostInterval {
    private let signposter: OSSignposter
    private let state: OSSignpostIntervalState

    public init(signposter: OSSignposter, name: StaticString, id: OSSignpostID = .exclusive) {
        self.signposter = signposter
        self.state = signposter.beginInterval(name, id: id)
    }

    public func end(name: StaticString, message: StaticString? = nil) {
        if let message {
            signposter.endInterval(name, state, "\(message)")
        } else {
            signposter.endInterval(name, state)
        }
    }
}

public enum Signpost {
    public static let imageLoading = OSSignposter(subsystem: AppLog.subsystem, category: "image_loading")
    public static let homeScroll = OSSignposter(subsystem: AppLog.subsystem, category: "home_scroll")
    public static let sync = OSSignposter(subsystem: AppLog.subsystem, category: "sync")
}

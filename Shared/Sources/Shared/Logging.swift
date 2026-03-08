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
    public static let nativeBridge = Logger(subsystem: subsystem, category: "nativeBridge")
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
    public static let playbackInfo = OSSignposter(subsystem: AppLog.subsystem, category: "playback_info")
    public static let playbackSelection = OSSignposter(subsystem: AppLog.subsystem, category: "playback_selection")
    public static let playerLifecycle = OSSignposter(subsystem: AppLog.subsystem, category: "player_lifecycle")
    public static let playbackStalls = OSSignposter(subsystem: AppLog.subsystem, category: "playback_stalls")
    public static let ttffPipeline = OSSignposter(subsystem: AppLog.subsystem, category: "ttff_pipeline")
    public static let nativeBridgePipeline = OSSignposter(subsystem: AppLog.subsystem, category: "native_bridge_pipeline")
}

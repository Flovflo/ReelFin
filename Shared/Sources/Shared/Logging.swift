import CryptoKit
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

public enum AppLogCorrelationDomain: String, CaseIterable, Sendable {
    case media
    case source
    case track
    case server
    case path
}

struct AppLogCorrelator: Sendable {
    private let key: SymmetricKey

    init(keyData: Data) {
        key = SymmetricKey(data: keyData)
    }

    fileprivate init(key: SymmetricKey) {
        self.key = key
    }

    func identifier(_ value: String?, domain: AppLogCorrelationDomain) -> String {
        guard let value, !value.isEmpty else { return "unknown" }
        var input = Data(domain.rawValue.utf8)
        input.append(0)
        input.append(contentsOf: value.utf8)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: input, using: key)
        return authenticationCode.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

public enum AppLogFormat {
    static let processCorrelator = AppLogCorrelator(key: SymmetricKey(size: .bits256))

    public static func correlationIdentifier(
        _ value: String?,
        domain: AppLogCorrelationDomain = .media
    ) -> String {
        processCorrelator.identifier(value, domain: domain)
    }

    public static func randomSessionIdentifier() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
    }
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

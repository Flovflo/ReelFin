import Foundation

public enum PlaybackVideoIntegrity: String, Codable, Sendable, Equatable {
    case originalBitstream
    case videoCopyRemux
    case audioOnlyTranscode
    case videoTranscode
    case unknown
}

public enum PlaybackHDRIntegrity: String, Codable, Sendable, Equatable {
    case dolbyVision
    case hdr10
    case hdr10FallbackFromDolbyVision
    case hlg
    case sdr
    case sdrToneMapped
    case unknown
}

public enum PlaybackStartupClass: String, Codable, Sendable, Equatable {
    case directLocal
    case directLAN
    case remoteDirect
    case progressiveRemux
    case hlsRemux
    case transcode
    case nativeDirect
    case unknown
}

public struct PlaybackRouteGuarantees: Codable, Sendable, Equatable {
    public let videoIntegrity: PlaybackVideoIntegrity
    public let hdrIntegrity: PlaybackHDRIntegrity
    public let startupClass: PlaybackStartupClass
    public let userVisibleSummary: String
    public let debugReason: String

    public init(
        videoIntegrity: PlaybackVideoIntegrity,
        hdrIntegrity: PlaybackHDRIntegrity,
        startupClass: PlaybackStartupClass,
        userVisibleSummary: String,
        debugReason: String
    ) {
        self.videoIntegrity = videoIntegrity
        self.hdrIntegrity = hdrIntegrity
        self.startupClass = startupClass
        self.userVisibleSummary = userVisibleSummary
        self.debugReason = debugReason
    }

    public var preservesOriginalVideo: Bool {
        switch videoIntegrity {
        case .originalBitstream, .videoCopyRemux, .audioOnlyTranscode:
            return true
        case .videoTranscode, .unknown:
            return false
        }
    }

    public var preservesDolbyVision: Bool {
        hdrIntegrity == .dolbyVision
    }

    public var preservesHDR: Bool {
        switch hdrIntegrity {
        case .dolbyVision, .hdr10, .hdr10FallbackFromDolbyVision, .hlg:
            return true
        case .sdr, .sdrToneMapped, .unknown:
            return false
        }
    }

    public var isVideoTranscode: Bool {
        videoIntegrity == .videoTranscode
    }

    public var isAudioOnlyTranscode: Bool {
        videoIntegrity == .audioOnlyTranscode
    }

    public static let unknown = PlaybackRouteGuarantees(
        videoIntegrity: .unknown,
        hdrIntegrity: .unknown,
        startupClass: .unknown,
        userVisibleSummary: "Playback quality unknown",
        debugReason: "Route guarantees have not been resolved."
    )
}

public struct PlaybackRouteEvidence: Sendable, Equatable {
    public var selectedVariantAllowsVideoCopy: Bool?
    public var selectedVariantIsDolbyVisionSignaled: Bool
    public var selectedVariantIsHDRSignaled: Bool
    public var selectedVariantUsesFMP4: Bool?
    public var selectedVariantCodec: String?
    public var initHasHvcC: Bool
    public var initHasDvcC: Bool
    public var initHasDvvC: Bool
    public var localGatewayEnabled: Bool
    public var localGatewayObservedBitrate: Int?

    public init(
        selectedVariantAllowsVideoCopy: Bool? = nil,
        selectedVariantIsDolbyVisionSignaled: Bool = false,
        selectedVariantIsHDRSignaled: Bool = false,
        selectedVariantUsesFMP4: Bool? = nil,
        selectedVariantCodec: String? = nil,
        initHasHvcC: Bool = false,
        initHasDvcC: Bool = false,
        initHasDvvC: Bool = false,
        localGatewayEnabled: Bool = false,
        localGatewayObservedBitrate: Int? = nil
    ) {
        self.selectedVariantAllowsVideoCopy = selectedVariantAllowsVideoCopy
        self.selectedVariantIsDolbyVisionSignaled = selectedVariantIsDolbyVisionSignaled
        self.selectedVariantIsHDRSignaled = selectedVariantIsHDRSignaled
        self.selectedVariantUsesFMP4 = selectedVariantUsesFMP4
        self.selectedVariantCodec = selectedVariantCodec
        self.initHasHvcC = initHasHvcC
        self.initHasDvcC = initHasDvcC
        self.initHasDvvC = initHasDvvC
        self.localGatewayEnabled = localGatewayEnabled
        self.localGatewayObservedBitrate = localGatewayObservedBitrate
    }
}

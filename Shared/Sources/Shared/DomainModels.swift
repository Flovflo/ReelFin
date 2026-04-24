import CoreGraphics
import Foundation

public enum MediaType: String, Codable, CaseIterable, Sendable {
    case movie
    case series
    case episode
    case season
    case unknown
}

public enum HomeSectionKind: String, Codable, CaseIterable, Sendable {
    case continueWatching
    case recentlyReleasedMovies
    case recentlyReleasedSeries
    case nextUp
    case recentlyAddedMovies
    case recentlyAddedSeries
    case popular
    case trending
    case movies
    case shows
    case latest
}

public enum QualityPreference: String, Codable, CaseIterable, Sendable {
    case auto
    case p1080
    case p720
    case p480

    public var maxStreamingBitrate: Int {
        switch self {
        case .auto:
            return 120_000_000
        case .p1080:
            return 20_000_000
        case .p720:
            return 8_000_000
        case .p480:
            return 3_500_000
        }
    }
}

public enum PlaybackStrategy: String, Codable, CaseIterable, Sendable {
    case bestQualityFastest
    case directRemuxOnly
}

public enum PlaybackPolicy: String, Codable, CaseIterable, Sendable {
    case auto
    case originalFirst
    case originalLockHDRDV
}

public struct ServerConfiguration: Codable, Hashable, Sendable {
    public var serverURL: URL
    public var allowCellularStreaming: Bool
    public var preferredQuality: QualityPreference
    public var playbackStrategy: PlaybackStrategy
    public var playbackPolicy: PlaybackPolicy
    public var allowSDRFallback: Bool
    public var preferAudioTranscodeOnly: Bool
    public var maxStreamingBitrateOverride: Int?
    public var forceH264FallbackWhenNotDirectPlay: Bool
    public var nativeVLCClassPlayerConfig: NativeVLCClassPlayerConfig
    /// BCP-47 / ISO 639 language tag for preferred audio track selection (e.g. "fr", "en", "de").
    /// When set this is the primary signal for audio track choice — it beats codec prestige.
    /// nil means "use the track flagged as default, or the first native-compatible track".
    public var preferredAudioLanguage: String?
    /// BCP-47 / ISO 639 language tag for preferred subtitle track selection (e.g. "fr", "en").
    /// Used for initial auto-selection of forced or default subtitle tracks at startup.
    public var preferredSubtitleLanguage: String?

    public init(
        serverURL: URL,
        allowCellularStreaming: Bool = true,
        preferredQuality: QualityPreference = .auto,
        playbackStrategy: PlaybackStrategy = .bestQualityFastest,
        playbackPolicy: PlaybackPolicy = .auto,
        allowSDRFallback: Bool? = nil,
        preferAudioTranscodeOnly: Bool = true,
        maxStreamingBitrateOverride: Int? = nil,
        forceH264FallbackWhenNotDirectPlay: Bool = false,
        nativeVLCClassPlayerConfig: NativeVLCClassPlayerConfig = NativeVLCClassPlayerConfig(),
        preferredAudioLanguage: String? = nil,
        preferredSubtitleLanguage: String? = nil
    ) {
        self.serverURL = serverURL
        self.allowCellularStreaming = allowCellularStreaming
        self.preferredQuality = preferredQuality
        self.playbackStrategy = playbackStrategy
        self.playbackPolicy = playbackPolicy
        self.allowSDRFallback = allowSDRFallback ?? (playbackPolicy == .originalLockHDRDV ? false : true)
        self.preferAudioTranscodeOnly = preferAudioTranscodeOnly
        self.maxStreamingBitrateOverride = maxStreamingBitrateOverride
        self.forceH264FallbackWhenNotDirectPlay = forceH264FallbackWhenNotDirectPlay
        self.nativeVLCClassPlayerConfig = nativeVLCClassPlayerConfig
        self.preferredAudioLanguage = preferredAudioLanguage
        self.preferredSubtitleLanguage = preferredSubtitleLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case serverURL
        case allowCellularStreaming
        case preferredQuality
        case playbackStrategy
        case playbackPolicy
        case allowSDRFallback
        case preferAudioTranscodeOnly
        case maxStreamingBitrateOverride
        case forceH264FallbackWhenNotDirectPlay
        case nativeVLCClassPlayerConfig
        case preferredAudioLanguage
        case preferredSubtitleLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(URL.self, forKey: .serverURL)
        allowCellularStreaming = try container.decodeIfPresent(Bool.self, forKey: .allowCellularStreaming) ?? true
        preferredQuality = try container.decodeIfPresent(QualityPreference.self, forKey: .preferredQuality) ?? .auto
        playbackStrategy = try container.decodeIfPresent(PlaybackStrategy.self, forKey: .playbackStrategy) ?? .bestQualityFastest
        playbackPolicy = try container.decodeIfPresent(PlaybackPolicy.self, forKey: .playbackPolicy) ?? .auto
        allowSDRFallback = try container.decodeIfPresent(Bool.self, forKey: .allowSDRFallback)
            ?? (playbackPolicy == .originalLockHDRDV ? false : true)
        preferAudioTranscodeOnly = try container.decodeIfPresent(Bool.self, forKey: .preferAudioTranscodeOnly) ?? true
        maxStreamingBitrateOverride = try container.decodeIfPresent(Int.self, forKey: .maxStreamingBitrateOverride)
        forceH264FallbackWhenNotDirectPlay = try container.decodeIfPresent(Bool.self, forKey: .forceH264FallbackWhenNotDirectPlay) ?? false
        nativeVLCClassPlayerConfig = try container.decodeIfPresent(
            NativeVLCClassPlayerConfig.self,
            forKey: .nativeVLCClassPlayerConfig
        ) ?? NativeVLCClassPlayerConfig()
        preferredAudioLanguage = try container.decodeIfPresent(String.self, forKey: .preferredAudioLanguage)
        preferredSubtitleLanguage = try container.decodeIfPresent(String.self, forKey: .preferredSubtitleLanguage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(allowCellularStreaming, forKey: .allowCellularStreaming)
        try container.encode(preferredQuality, forKey: .preferredQuality)
        try container.encode(playbackStrategy, forKey: .playbackStrategy)
        try container.encode(playbackPolicy, forKey: .playbackPolicy)
        try container.encode(allowSDRFallback, forKey: .allowSDRFallback)
        try container.encode(preferAudioTranscodeOnly, forKey: .preferAudioTranscodeOnly)
        try container.encodeIfPresent(maxStreamingBitrateOverride, forKey: .maxStreamingBitrateOverride)
        try container.encode(forceH264FallbackWhenNotDirectPlay, forKey: .forceH264FallbackWhenNotDirectPlay)
        try container.encode(nativeVLCClassPlayerConfig, forKey: .nativeVLCClassPlayerConfig)
        try container.encodeIfPresent(preferredAudioLanguage, forKey: .preferredAudioLanguage)
        try container.encodeIfPresent(preferredSubtitleLanguage, forKey: .preferredSubtitleLanguage)
    }

    public var effectiveMaxStreamingBitrate: Int {
        maxStreamingBitrateOverride ?? preferredQuality.maxStreamingBitrate
    }
}

public struct UserCredentials: Codable, Hashable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct UserSession: Codable, Hashable, Sendable {
    public var userID: String
    public var username: String
    public var token: String

    public init(userID: String, username: String, token: String) {
        self.userID = userID
        self.username = username
        self.token = token
    }
}

public struct LibraryView: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var collectionType: String?

    public init(id: String, name: String, collectionType: String? = nil) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
    }
}

public extension LibraryView {
    var normalizedCollectionType: String? {
        collectionType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func supports(mediaType: MediaType) -> Bool {
        guard let normalizedCollectionType else { return false }

        switch mediaType {
        case .movie:
            return ["movie", "movies"].contains(normalizedCollectionType)
        case .series:
            return ["series", "show", "shows", "tvshow", "tvshows"].contains(normalizedCollectionType)
        case .episode, .season, .unknown:
            return false
        }
    }
}

public struct MediaItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var overview: String?
    public var mediaType: MediaType
    public var year: Int?
    public var runtimeTicks: Int64?
    public var genres: [String]
    public var communityRating: Double?
    public var posterTag: String?
    public var backdropTag: String?
    public var libraryID: String?
    public var parentID: String?
    public var seriesName: String?
    public var seriesPosterTag: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    public var has4K: Bool
    public var hasDolbyVision: Bool
    public var hasClosedCaptions: Bool
    public var airDays: [String]?
    public var isFavorite: Bool
    public var isPlayed: Bool
    public var playbackPositionTicks: Int64?

    public init(
        id: String,
        name: String,
        overview: String? = nil,
        mediaType: MediaType = .unknown,
        year: Int? = nil,
        runtimeTicks: Int64? = nil,
        genres: [String] = [],
        communityRating: Double? = nil,
        posterTag: String? = nil,
        backdropTag: String? = nil,
        libraryID: String? = nil,
        parentID: String? = nil,
        seriesName: String? = nil,
        seriesPosterTag: String? = nil,
        indexNumber: Int? = nil,
        parentIndexNumber: Int? = nil,
        has4K: Bool = false,
        hasDolbyVision: Bool = false,
        hasClosedCaptions: Bool = false,
        airDays: [String]? = nil,
        isFavorite: Bool = false,
        isPlayed: Bool = false,
        playbackPositionTicks: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.mediaType = mediaType
        self.year = year
        self.runtimeTicks = runtimeTicks
        self.genres = genres
        self.communityRating = communityRating
        self.posterTag = posterTag
        self.backdropTag = backdropTag
        self.libraryID = libraryID
        self.parentID = parentID
        self.seriesName = seriesName
        self.seriesPosterTag = seriesPosterTag
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.has4K = has4K
        self.hasDolbyVision = hasDolbyVision
        self.hasClosedCaptions = hasClosedCaptions
        self.airDays = airDays
        self.isFavorite = isFavorite
        self.isPlayed = isPlayed
        self.playbackPositionTicks = playbackPositionTicks
    }

    public var runtimeMinutes: Int? {
        guard let runtimeTicks else { return nil }
        return Int(runtimeTicks / 10_000_000 / 60)
    }

    public var runtimeDisplayText: String? {
        guard let runtimeMinutes else { return nil }
        return Self.formatMinutes(runtimeMinutes)
    }

    public var playbackPositionDisplayText: String? {
        guard !isPlayed, let playbackPositionTicks, playbackPositionTicks > 0 else { return nil }
        let totalSeconds = Int(playbackPositionTicks / 10_000_000)
        return Self.formatDuration(seconds: totalSeconds)
    }

    public var playbackProgress: Double? {
        guard !isPlayed, let position = playbackPositionTicks, let total = runtimeTicks, total > 0 else {
            return nil
        }
        return min(1, max(0, Double(position) / Double(total)))
    }

    private static func formatMinutes(_ totalMinutes: Int) -> String {
        guard totalMinutes >= 60 else { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours)h"
        }
        return String(format: "%dh%02d", hours, minutes)
    }

    private static func formatDuration(seconds: Int) -> String {
        let totalMinutes = max(0, seconds / 60)
        return formatMinutes(totalMinutes)
    }
}

public struct HomeRow: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: HomeSectionKind
    public var title: String
    public var items: [MediaItem]

    public init(id: String? = nil, kind: HomeSectionKind, title: String, items: [MediaItem]) {
        self.id = id ?? Self.defaultID(kind: kind, title: title)
        self.kind = kind
        self.title = title
        self.items = items
    }

    private static func defaultID(kind: HomeSectionKind, title: String) -> String {
        "home.\(kind.rawValue).\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

public struct HomeFeed: Codable, Hashable, Sendable {
    public var featured: [MediaItem]
    public var rows: [HomeRow]

    public init(featured: [MediaItem], rows: [HomeRow]) {
        self.featured = featured
        self.rows = rows
    }

    public static let empty = HomeFeed(featured: [], rows: [])
}

public struct PersonCredit: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var role: String?
    public var primaryImageTag: String?

    public init(id: String, name: String, role: String? = nil, primaryImageTag: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.primaryImageTag = primaryImageTag
    }
}

public struct MediaTrack: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var language: String?
    public var codec: String?
    public var isDefault: Bool
    public var isForced: Bool
    public var index: Int

    public init(
        id: String,
        title: String,
        language: String? = nil,
        codec: String? = nil,
        isDefault: Bool,
        isForced: Bool = false,
        index: Int
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.codec = codec
        self.isDefault = isDefault
        self.isForced = isForced
        self.index = index
    }
}

public struct MediaSource: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var itemID: String
    public var name: String
    public var filePath: String?
    public var fileSize: Int64?
    public var container: String?
    public var videoCodec: String?
    public var audioCodec: String?
    public var bitrate: Int?
    public var videoBitDepth: Int?
    public var videoRange: String?
    public var videoRangeType: String?
    public var videoProfile: String?
    public var dvProfile: Int?
    public var dvLevel: Int?
    public var dvBlSignalCompatibilityId: Int?
    public var hdr10PlusPresentFlag: Bool?
    public var colorPrimaries: String?
    public var colorTransfer: String?
    public var colorSpace: String?
    public var colorRange: String?
    public var audioChannels: Int?
    public var audioChannelLayout: String?
    public var audioProfile: String?
    public var supportsDirectPlay: Bool
    public var supportsDirectStream: Bool
    public var directStreamURL: URL?
    public var directPlayURL: URL?
    public var transcodeURL: URL?
    public var requiredHTTPHeaders: [String: String]
    public var audioTracks: [MediaTrack]
    public var subtitleTracks: [MediaTrack]
    public var videoWidth: Int?
    public var videoHeight: Int?
    public var videoFrameRate: Double?

    public init(
        id: String,
        itemID: String,
        name: String,
        filePath: String? = nil,
        fileSize: Int64? = nil,
        container: String? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        bitrate: Int? = nil,
        videoBitDepth: Int? = nil,
        videoRange: String? = nil,
        videoRangeType: String? = nil,
        videoProfile: String? = nil,
        dvProfile: Int? = nil,
        dvLevel: Int? = nil,
        dvBlSignalCompatibilityId: Int? = nil,
        hdr10PlusPresentFlag: Bool? = nil,
        colorPrimaries: String? = nil,
        colorTransfer: String? = nil,
        colorSpace: String? = nil,
        colorRange: String? = nil,
        audioChannels: Int? = nil,
        audioChannelLayout: String? = nil,
        audioProfile: String? = nil,
        supportsDirectPlay: Bool,
        supportsDirectStream: Bool,
        directStreamURL: URL? = nil,
        directPlayURL: URL? = nil,
        transcodeURL: URL? = nil,
        requiredHTTPHeaders: [String: String] = [:],
        audioTracks: [MediaTrack] = [],
        subtitleTracks: [MediaTrack] = [],
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        videoFrameRate: Double? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.name = name
        self.filePath = filePath
        self.fileSize = fileSize
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.bitrate = bitrate
        self.videoBitDepth = videoBitDepth
        self.videoRange = videoRange
        self.videoRangeType = videoRangeType
        self.videoProfile = videoProfile
        self.dvProfile = dvProfile
        self.dvLevel = dvLevel
        self.dvBlSignalCompatibilityId = dvBlSignalCompatibilityId
        self.hdr10PlusPresentFlag = hdr10PlusPresentFlag
        self.colorPrimaries = colorPrimaries
        self.colorTransfer = colorTransfer
        self.colorSpace = colorSpace
        self.colorRange = colorRange
        self.audioChannels = audioChannels
        self.audioChannelLayout = audioChannelLayout
        self.audioProfile = audioProfile
        self.supportsDirectPlay = supportsDirectPlay
        self.supportsDirectStream = supportsDirectStream
        self.directStreamURL = directStreamURL
        self.directPlayURL = directPlayURL
        self.transcodeURL = transcodeURL
        self.requiredHTTPHeaders = requiredHTTPHeaders
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.videoFrameRate = videoFrameRate
    }

    public var normalizedContainer: String {
        container?.lowercased() ?? ""
    }

    public var normalizedVideoCodec: String {
        videoCodec?.lowercased() ?? ""
    }

    public var normalizedAudioCodec: String {
        audioCodec?.lowercased() ?? ""
    }

    public var isLikely4K: Bool {
        (videoWidth ?? 0) >= 3_840 || (videoHeight ?? 0) >= 2_160
    }

    public var isLikelyHDRorDV: Bool {
        let range = (videoRange ?? "").lowercased()
        let rangeType = (videoRangeType ?? "").lowercased()
        let profile = (videoProfile ?? "").lowercased()
        let codec = normalizedVideoCodec
        return (videoBitDepth ?? 8) >= 10
            || range.contains("hdr")
            || rangeType.contains("dovi")
            || rangeType.contains("hdr10")
            || rangeType.contains("hlg")
            || range.contains("pq")
            || range.contains("hlg")
            || range.contains("dolby")
            || range.contains("vision")
            || profile.contains("dolby")
            || profile.contains("vision")
            || (dvProfile ?? 0) > 0
            || hdr10PlusPresentFlag == true
            || codec.contains("dvhe")
            || codec.contains("dvh1")
    }

    public var isPremiumVideoSource: Bool {
        let codec = normalizedVideoCodec
        let hevcLike = codec.contains("hevc")
            || codec.contains("h265")
            || codec.contains("dvh1")
            || codec.contains("dvhe")
            || codec.contains("hvc1")
            || codec.contains("hev1")
        return hevcLike && (isLikely4K || isLikelyHDRorDV)
    }
}

public enum PlaybackMode: String, Codable, CaseIterable, Sendable {
    case performance
    case balanced
}

public enum PlaybackDeviceProfile: String, Codable, CaseIterable, Sendable {
    case automatic
    case iosOptimizedHEVC
    case iosCompatibilityH264
    case tvOSOptimized
    case tvOSSimulatorCompatibilityH264
}

public struct PlaybackInfoOptions: Codable, Hashable, Sendable {
    public var mode: PlaybackMode
    public var enableDirectPlay: Bool
    public var enableDirectStream: Bool
    public var allowTranscoding: Bool
    public var maxStreamingBitrate: Int?
    public var startTimeTicks: Int64?
    public var allowVideoStreamCopy: Bool?
    public var allowAudioStreamCopy: Bool?
    public var maxAudioChannels: Int?
    public var deviceProfile: PlaybackDeviceProfile?

    public init(
        mode: PlaybackMode = .balanced,
        enableDirectPlay: Bool = true,
        enableDirectStream: Bool = true,
        allowTranscoding: Bool = true,
        maxStreamingBitrate: Int? = nil,
        startTimeTicks: Int64? = nil,
        allowVideoStreamCopy: Bool? = nil,
        allowAudioStreamCopy: Bool? = nil,
        maxAudioChannels: Int? = nil,
        deviceProfile: PlaybackDeviceProfile? = nil
    ) {
        self.mode = mode
        self.enableDirectPlay = enableDirectPlay
        self.enableDirectStream = enableDirectStream
        self.allowTranscoding = allowTranscoding
        self.maxStreamingBitrate = maxStreamingBitrate
        self.startTimeTicks = startTimeTicks
        self.allowVideoStreamCopy = allowVideoStreamCopy
        self.allowAudioStreamCopy = allowAudioStreamCopy
        self.maxAudioChannels = maxAudioChannels
        self.deviceProfile = deviceProfile
    }

    public static func performance(maxStreamingBitrate: Int?) -> PlaybackInfoOptions {
        PlaybackInfoOptions(
            mode: .performance,
            enableDirectPlay: true,
            enableDirectStream: true,
            allowTranscoding: false,
            maxStreamingBitrate: maxStreamingBitrate
        )
    }

    public static func balanced(maxStreamingBitrate: Int?) -> PlaybackInfoOptions {
        PlaybackInfoOptions(
            mode: .balanced,
            enableDirectPlay: true,
            enableDirectStream: true,
            allowTranscoding: true,
            maxStreamingBitrate: maxStreamingBitrate
        )
    }

    public static func appleOptimizedHEVC(maxStreamingBitrate: Int?) -> PlaybackInfoOptions {
        let bitrate = min(maxStreamingBitrate ?? 30_000_000, 30_000_000)
        return PlaybackInfoOptions(
            mode: .balanced,
            enableDirectPlay: false,
            enableDirectStream: false,
            allowTranscoding: true,
            maxStreamingBitrate: bitrate,
            allowVideoStreamCopy: false,
            allowAudioStreamCopy: false,
            maxAudioChannels: 6,
            deviceProfile: .iosOptimizedHEVC
        )
    }

    public static func compatibilityH264(maxStreamingBitrate: Int?) -> PlaybackInfoOptions {
        let bitrate = min(maxStreamingBitrate ?? 12_000_000, 12_000_000)
        return PlaybackInfoOptions(
            mode: .balanced,
            enableDirectPlay: false,
            enableDirectStream: false,
            allowTranscoding: true,
            maxStreamingBitrate: bitrate,
            allowVideoStreamCopy: false,
            allowAudioStreamCopy: false,
            maxAudioChannels: 2,
            deviceProfile: .iosCompatibilityH264
        )
    }

    /// tvOS-optimized profile for Apple TV 4K.
    /// Enables direct play for compatible containers, DirectStream (remux) for MKV,
    /// and requests server-side HLS fMP4 HEVC transcode for incompatible codecs.
    public static func tvOSOptimized(maxStreamingBitrate: Int?) -> PlaybackInfoOptions {
        let bitrate = min(maxStreamingBitrate ?? 80_000_000, 80_000_000)
        return PlaybackInfoOptions(
            mode: .balanced,
            enableDirectPlay: true,
            enableDirectStream: true,
            allowTranscoding: true,
            maxStreamingBitrate: bitrate,
            allowVideoStreamCopy: true,
            allowAudioStreamCopy: true,
            maxAudioChannels: 8,
            deviceProfile: .tvOSOptimized
        )
    }

    public static func tvOSSimulatorCompatibility(maxStreamingBitrate: Int?) -> PlaybackInfoOptions {
        let bitrate = min(maxStreamingBitrate ?? 12_000_000, 12_000_000)
        return PlaybackInfoOptions(
            mode: .balanced,
            enableDirectPlay: true,
            enableDirectStream: false,
            allowTranscoding: true,
            maxStreamingBitrate: bitrate,
            allowVideoStreamCopy: false,
            allowAudioStreamCopy: false,
            maxAudioChannels: 2,
            deviceProfile: .tvOSSimulatorCompatibilityH264
        )
    }
}

public struct MediaDetail: Codable, Hashable, Sendable {
    public var item: MediaItem
    public var similar: [MediaItem]
    public var cast: [PersonCredit]

    public init(item: MediaItem, similar: [MediaItem] = [], cast: [PersonCredit] = []) {
        self.item = item
        self.similar = similar
        self.cast = cast
    }
}

public struct TrickplayManifest: Codable, Hashable, Sendable {
    public var itemID: String
    public var sourceID: String?
    public var variants: [TrickplayVariant]

    public init(itemID: String, sourceID: String?, variants: [TrickplayVariant]) {
        self.itemID = itemID
        self.sourceID = sourceID
        self.variants = variants.sorted { lhs, rhs in
            if lhs.width == rhs.width {
                return lhs.bandwidth ?? 0 < rhs.bandwidth ?? 0
            }
            return lhs.width < rhs.width
        }
    }

    public func preferredVariant(forThumbnailWidth preferredWidth: Int) -> TrickplayVariant? {
        guard !variants.isEmpty else { return nil }
        let minimumWidth = max(1, preferredWidth)
        return variants.first(where: { $0.width >= minimumWidth }) ?? variants.last
    }
}

public struct TrickplayVariant: Codable, Hashable, Identifiable, Sendable {
    public var id: Int { width }
    public var width: Int
    public var height: Int
    public var tileWidth: Int
    public var tileHeight: Int
    public var thumbnailCount: Int
    public var intervalMilliseconds: Int
    public var bandwidth: Int?

    public init(
        width: Int,
        height: Int,
        tileWidth: Int,
        tileHeight: Int,
        thumbnailCount: Int,
        intervalMilliseconds: Int,
        bandwidth: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.thumbnailCount = thumbnailCount
        self.intervalMilliseconds = intervalMilliseconds
        self.bandwidth = bandwidth
    }

    public var thumbnailsPerTileImage: Int {
        max(1, tileWidth * tileHeight)
    }

    public func frame(for seconds: Double) -> TrickplayFrame? {
        guard
            width > 0,
            height > 0,
            tileWidth > 0,
            tileHeight > 0,
            thumbnailCount > 0,
            intervalMilliseconds > 0
        else {
            return nil
        }

        let clampedSeconds = max(0, seconds)
        let rawIndex = Int((clampedSeconds * 1_000).rounded(.down)) / intervalMilliseconds
        let thumbnailIndex = min(rawIndex, thumbnailCount - 1)
        let tileImageIndex = thumbnailIndex / thumbnailsPerTileImage
        let tileSlotIndex = thumbnailIndex % thumbnailsPerTileImage
        let column = tileSlotIndex % tileWidth
        let row = tileSlotIndex / tileWidth

        return TrickplayFrame(
            thumbnailIndex: thumbnailIndex,
            tileImageIndex: tileImageIndex,
            column: column,
            row: row,
            width: width,
            height: height
        )
    }
}

public struct TrickplayFrame: Codable, Hashable, Sendable {
    public var thumbnailIndex: Int
    public var tileImageIndex: Int
    public var column: Int
    public var row: Int
    public var width: Int
    public var height: Int

    public init(
        thumbnailIndex: Int,
        tileImageIndex: Int,
        column: Int,
        row: Int,
        width: Int,
        height: Int
    ) {
        self.thumbnailIndex = thumbnailIndex
        self.tileImageIndex = tileImageIndex
        self.column = column
        self.row = row
        self.width = width
        self.height = height
    }

    public var cropRect: CGRect {
        CGRect(
            x: CGFloat(column * width),
            y: CGFloat(row * height),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

public enum JellyfinImageType: String, Codable, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case logo = "Logo"
}

public struct PlaybackProgressUpdate: Codable, Hashable, Sendable {
    public var itemID: String
    public var positionTicks: Int64
    public var totalTicks: Int64
    public var isPaused: Bool
    public var isPlaying: Bool
    public var didFinish: Bool
    public var playMethod: String?

    public init(
        itemID: String,
        positionTicks: Int64,
        totalTicks: Int64,
        isPaused: Bool,
        isPlaying: Bool,
        didFinish: Bool,
        playMethod: String? = nil
    ) {
        self.itemID = itemID
        self.positionTicks = positionTicks
        self.totalTicks = totalTicks
        self.isPaused = isPaused
        self.isPlaying = isPlaying
        self.didFinish = didFinish
        self.playMethod = playMethod
    }
}

public struct PlaybackProgress: Codable, Hashable, Sendable {
    public var itemID: String
    public var positionTicks: Int64
    public var totalTicks: Int64
    public var updatedAt: Date

    public init(itemID: String, positionTicks: Int64, totalTicks: Int64, updatedAt: Date) {
        self.itemID = itemID
        self.positionTicks = positionTicks
        self.totalTicks = totalTicks
        self.updatedAt = updatedAt
    }

    public var progressRatio: Double {
        guard totalTicks > 0 else { return 0 }
        return min(1, max(0, Double(positionTicks) / Double(totalTicks)))
    }

    public static func resolvedResumeProgress(
        for item: MediaItem,
        localProgress: PlaybackProgress?,
        referenceDate: Date = Date()
    ) -> PlaybackProgress? {
        guard !item.isPlayed else { return nil }

        let local = normalizedLocalProgress(localProgress, matching: item.id)
        let server = serverProgress(for: item, referenceDate: referenceDate)

        switch (local, server) {
        case let (local?, server?):
            return server.positionTicks > local.positionTicks ? server : local
        case let (local?, nil):
            return local
        case let (nil, server?):
            return server
        case (nil, nil):
            return nil
        }
    }

    private static func normalizedLocalProgress(
        _ progress: PlaybackProgress?,
        matching itemID: String
    ) -> PlaybackProgress? {
        guard var progress, progress.itemID == itemID, progress.positionTicks > 0 else {
            return nil
        }

        progress.totalTicks = max(progress.totalTicks, progress.positionTicks)
        return progress
    }

    private static func serverProgress(
        for item: MediaItem,
        referenceDate: Date
    ) -> PlaybackProgress? {
        guard let positionTicks = item.playbackPositionTicks, positionTicks > 0 else {
            return nil
        }

        return PlaybackProgress(
            itemID: item.id,
            positionTicks: positionTicks,
            totalTicks: max(item.runtimeTicks ?? 0, positionTicks),
            updatedAt: referenceDate
        )
    }
}

public struct LibraryQuery: Hashable, Sendable {
    public var viewID: String?
    public var viewIDs: [String]?
    public var page: Int
    public var pageSize: Int
    public var query: String?
    public var mediaType: MediaType?

    public init(viewID: String?, page: Int, pageSize: Int, query: String?, mediaType: MediaType?) {
        self.viewID = viewID
        viewIDs = nil
        self.page = page
        self.pageSize = pageSize
        self.query = query
        self.mediaType = mediaType
    }

    public init(viewIDs: [String], page: Int, pageSize: Int, query: String?, mediaType: MediaType?) {
        let normalizedIDs = Self.normalizedViewIDs(from: viewIDs)
        viewID = normalizedIDs.count == 1 ? normalizedIDs.first : nil
        self.viewIDs = normalizedIDs.isEmpty ? nil : normalizedIDs
        self.page = page
        self.pageSize = pageSize
        self.query = query
        self.mediaType = mediaType
    }

    public var resolvedViewIDs: [String] {
        if let viewIDs, !viewIDs.isEmpty {
            return Self.normalizedViewIDs(from: viewIDs)
        }

        guard
            let viewID,
            !viewID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return []
        }

        return [viewID]
    }

    private static func normalizedViewIDs(from viewIDs: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for candidate in viewIDs {
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }
}

/// Holds the active Quick Connect handshake state.
public struct QuickConnectState: Sendable {
    /// 4-character code shown to the user on Apple TV.
    public let code: String
    /// Opaque secret used to poll the server.
    public let secret: String

    public init(code: String, secret: String) {
        self.code = code
        self.secret = secret
    }
}

import Foundation
import Shared

/// Decodes a JSON array while silently skipping elements that fail to decode.
/// This prevents a single malformed item from crashing the entire response.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                // Skip the bad element by decoding as throwaway JSON
                _ = try? container.decode(AnyCodable.self)
            }
        }
        self.elements = result
    }
}

private struct AnyCodable: Decodable {}

struct AuthenticateRequestDTO: Encodable {
    let username: String
    let pw: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case pw = "Pw"
    }
}

struct AuthenticateResponseDTO: Decodable {
    let user: UserDTO
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
    }
}

struct UserDTO: Decodable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

struct ViewsResponseDTO: Decodable {
    let items: [ViewDTO]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = (try? container.decodeIfPresent(LossyArray<ViewDTO>.self, forKey: .items))?.elements ?? []
    }
}

struct ViewDTO: Decodable {
    let id: String
    let name: String
    let collectionType: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
    }
}

struct ItemsResponseDTO: Decodable {
    let items: [ItemDTO]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = (try? container.decodeIfPresent(LossyArray<ItemDTO>.self, forKey: .items))?.elements ?? []
    }

    init(items: [ItemDTO]) {
        self.items = items
    }
}

struct ItemDTO: Decodable {
    let id: String
    let name: String
    let overview: String?
    let type: String?
    let productionYear: Int?
    let runTimeTicks: Int64?
    let genres: [String]?
    let communityRating: Double?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let parentID: String?
    let seriesID: String?
    let seriesName: String?
    let seriesPrimaryImageTag: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let people: [PersonDTO]?
    let mediaStreams: [MediaStreamDTO]?
    let airDays: [String]?
    let userData: UserDataDTO?
    let trickplay: [String: [Int: TrickplayInfoDTO]]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case overview = "Overview"
        case type = "Type"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case genres = "Genres"
        case communityRating = "CommunityRating"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentID = "ParentId"
        case seriesID = "SeriesId"
        case seriesName = "SeriesName"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case people = "People"
        case mediaStreams = "MediaStreams"
        case airDays = "AirDays"
        case userData = "UserData"
        case trickplay = "Trickplay"
    }

    init(
        id: String,
        name: String,
        overview: String? = nil,
        type: String? = nil,
        productionYear: Int? = nil,
        runTimeTicks: Int64? = nil,
        genres: [String]? = nil,
        communityRating: Double? = nil,
        imageTags: [String: String]? = nil,
        backdropImageTags: [String]? = nil,
        parentID: String? = nil,
        seriesID: String? = nil,
        seriesName: String? = nil,
        seriesPrimaryImageTag: String? = nil,
        indexNumber: Int? = nil,
        parentIndexNumber: Int? = nil,
        people: [PersonDTO]? = nil,
        mediaStreams: [MediaStreamDTO]? = nil,
        airDays: [String]? = nil,
        userData: UserDataDTO? = nil,
        trickplay: [String: [Int: TrickplayInfoDTO]]? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.type = type
        self.productionYear = productionYear
        self.runTimeTicks = runTimeTicks
        self.genres = genres
        self.communityRating = communityRating
        self.imageTags = imageTags
        self.backdropImageTags = backdropImageTags
        self.parentID = parentID
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seriesPrimaryImageTag = seriesPrimaryImageTag
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.people = people
        self.mediaStreams = mediaStreams
        self.airDays = airDays
        self.userData = userData
        self.trickplay = trickplay
    }

    func toDomain(libraryID: String? = nil) -> MediaItem {
        let mediaType: MediaType
        switch type?.lowercased() {
        case "movie":
            mediaType = .movie
        case "series":
            mediaType = .series
        case "episode":
            mediaType = .episode
        case "season":
            mediaType = .season
        default:
            mediaType = .unknown
        }

        var has4K = false
        var hasDolbyVision = false
        var hasClosedCaptions = false

        if let streams = mediaStreams {
            has4K = streams.contains { 
                $0.type?.lowercased() == "video" && 
                (($0.width ?? 0) >= 3840 || ($0.height ?? 0) >= 2160 || ($0.displayTitle?.lowercased().contains("4k") == true)) 
            }
            hasDolbyVision = streams.contains { stream in
                guard stream.type?.lowercased() == "video" else { return false }

                let rangeType = stream.videoRangeType?.lowercased() ?? ""
                let profile = stream.profile?.lowercased() ?? ""
                let displayTitle = stream.displayTitle?.lowercased() ?? ""
                let codec = stream.codec?.lowercased() ?? ""

                if rangeType == "dovi" || rangeType == "dv" || rangeType == "dolbyvision" || rangeType.contains("dolby vision") {
                    return true
                }

                let metadata = "\(profile) \(displayTitle)"
                if metadata.contains("dolby vision") || metadata.contains("dolbyvision") || metadata.contains("dvhe") || metadata.contains("dvh1") {
                    return true
                }

                return codec.contains("dvhe") || codec.contains("dvh1")
            }
            hasClosedCaptions = streams.contains { $0.type?.lowercased() == "subtitle" }
        }

        return MediaItem(
            id: id,
            name: name,
            overview: overview,
            mediaType: mediaType,
            year: productionYear,
            runtimeTicks: runTimeTicks,
            genres: genres ?? [],
            communityRating: communityRating,
            posterTag: imageTags?["Primary"],
            backdropTag: backdropImageTags?.first,
            libraryID: libraryID,
            parentID: parentID ?? seriesID,
            seriesName: seriesName,
            seriesPosterTag: seriesPrimaryImageTag,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber,
            has4K: has4K,
            hasDolbyVision: hasDolbyVision,
            hasClosedCaptions: hasClosedCaptions,
            airDays: airDays,
            isFavorite: userData?.isFavorite ?? false,
            isPlayed: userData?.played ?? false,
            playbackPositionTicks: userData?.playbackPositionTicks
        )
    }

    func toTrickplayManifest(
        preferredSourceID: String?,
        fallbackItemID: String
    ) -> TrickplayManifest? {
        guard let trickplay, !trickplay.isEmpty else { return nil }

        let selectedEntry =
            preferredSourceID.flatMap { sourceID in trickplay[sourceID].map { (sourceID, $0) } }
            ?? trickplay[fallbackItemID].map { (fallbackItemID, $0) }
            ?? trickplay.first

        guard let (selectedSourceID, selectedVariants) = selectedEntry else { return nil }

        let variants = selectedVariants.values.compactMap(\.toDomain)
        guard !variants.isEmpty else { return nil }

        return TrickplayManifest(
            itemID: fallbackItemID,
            sourceID: selectedSourceID == fallbackItemID ? nil : selectedSourceID,
            variants: variants
        )
    }
}

struct TrickplayInfoDTO: Decodable {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailCount: Int
    let interval: Int
    let bandwidth: Int?

    enum CodingKeys: String, CodingKey {
        case width = "Width"
        case height = "Height"
        case tileWidth = "TileWidth"
        case tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount"
        case interval = "Interval"
        case bandwidth = "Bandwidth"
    }

    var toDomain: TrickplayVariant? {
        guard
            width > 0,
            height > 0,
            tileWidth > 0,
            tileHeight > 0,
            thumbnailCount > 0,
            interval > 0
        else {
            return nil
        }

        return TrickplayVariant(
            width: width,
            height: height,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            thumbnailCount: thumbnailCount,
            intervalMilliseconds: interval,
            bandwidth: bandwidth
        )
    }
}

struct UserDataDTO: Decodable {
    let isFavorite: Bool?
    let played: Bool?
    let playbackPositionTicks: Int64?
    let playCount: Int?

    enum CodingKeys: String, CodingKey {
        case isFavorite = "IsFavorite"
        case played = "Played"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
    }
}

struct PersonDTO: Decodable {
    let id: String
    let name: String
    let role: String?
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case role = "Role"
        case primaryImageTag = "PrimaryImageTag"
    }

    func toDomain() -> PersonCredit {
        PersonCredit(id: id, name: name, role: role, primaryImageTag: primaryImageTag)
    }
}

struct PlaybackInfoResponseDTO: Decodable {
    // OpenAPI source:
    // /Users/florian/Downloads/jellyfin-openapi-stable.json
    // $.components.schemas.PlaybackInfoResponse.properties.MediaSources
    let mediaSources: [MediaSourceDTO]

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mediaSources = (try? container.decodeIfPresent(LossyArray<MediaSourceDTO>.self, forKey: .mediaSources))?.elements ?? []
    }
}

struct MediaSourceDTO: Decodable {
    // OpenAPI source:
    // /Users/florian/Downloads/jellyfin-openapi-stable.json
    // $.components.schemas.MediaSourceInfo
    let id: String
    let name: String?
    let path: String?
    let size: Int64?
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let bitrate: Int?
    let videoBitDepth: Int?
    let videoRangeType: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let directStreamURL: String?
    let transcodingURL: String?
    let requiredHTTPHeaders: [String: String]?
    let mediaStreams: [MediaStreamDTO]?

    init(
        id: String,
        name: String?,
        path: String? = nil,
        size: Int64? = nil,
        container: String?,
        videoCodec: String?,
        audioCodec: String?,
        bitrate: Int? = nil,
        videoBitDepth: Int? = nil,
        videoRangeType: String? = nil,
        supportsDirectPlay: Bool?,
        supportsDirectStream: Bool?,
        directStreamURL: String?,
        transcodingURL: String?,
        requiredHTTPHeaders: [String: String]? = nil,
        mediaStreams: [MediaStreamDTO]?
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.bitrate = bitrate
        self.videoBitDepth = videoBitDepth
        self.videoRangeType = videoRangeType
        self.supportsDirectPlay = supportsDirectPlay
        self.supportsDirectStream = supportsDirectStream
        self.directStreamURL = directStreamURL
        self.transcodingURL = transcodingURL
        self.requiredHTTPHeaders = requiredHTTPHeaders
        self.mediaStreams = mediaStreams
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case path = "Path"
        case size = "Size"
        case container = "Container"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
        case bitrate = "Bitrate"
        case videoBitDepth = "VideoBitDepth"
        case videoRangeType = "VideoRangeType"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case directStreamURL = "DirectStreamUrl"
        case transcodingURL = "TranscodingUrl"
        case requiredHTTPHeaders = "RequiredHttpHeaders"
        case mediaStreams = "MediaStreams"
    }

    func toDomain(itemID: String, serverURL: URL) -> MediaSource {
        let tracks = mediaStreams ?? []
        let audioStreams = tracks.filter { $0.type?.lowercased() == "audio" }
        let audioTracks = audioStreams.map { $0.toTrack(streamCodec: $0.codec) }
        let subtitleTracks = tracks.filter { $0.type?.lowercased() == "subtitle" }.map { $0.toTrack(streamCodec: $0.codec) }
        let videoStream = tracks.first(where: { $0.type?.lowercased() == "video" })
        let audioStream = preferredAppleAudioStream(from: audioStreams)

        let streamURL = directStreamURL.flatMap { resolvePlaybackURL($0, serverURL: serverURL) }
        let transcode = transcodingURL.flatMap { resolvePlaybackURL($0, serverURL: serverURL) }

        return MediaSource(
            id: id,
            itemID: itemID,
            name: name ?? "Source",
            filePath: path,
            fileSize: size,
            container: container,
            videoCodec: videoCodec ?? videoStream?.codec,
            audioCodec: preferredAppleAudioCodec(explicit: audioCodec, fallback: audioStream?.codec),
            bitrate: bitrate ?? videoStream?.bitrate,
            videoBitDepth: videoBitDepth ?? videoStream?.bitDepth,
            videoRange: videoRangeType ?? videoStream?.videoRangeType ?? videoStream?.videoRange,
            videoRangeType: videoRangeType ?? videoStream?.videoRangeType,
            videoProfile: videoStream?.profile,
            dvProfile: videoStream?.dvProfile,
            dvLevel: videoStream?.dvLevel,
            dvBlSignalCompatibilityId: videoStream?.dvBlSignalCompatibilityId,
            hdr10PlusPresentFlag: videoStream?.hdr10PlusPresentFlag,
            colorPrimaries: videoStream?.colorPrimaries,
            colorTransfer: videoStream?.colorTransfer,
            colorSpace: videoStream?.colorSpace,
            colorRange: videoStream?.colorRange,
            audioChannels: audioStream?.channels,
            audioChannelLayout: audioStream?.channelLayout,
            audioProfile: audioStream?.profile,
            supportsDirectPlay: supportsDirectPlay ?? false,
            supportsDirectStream: supportsDirectStream ?? false,
            directStreamURL: streamURL,
            directPlayURL: streamURL,
            transcodeURL: transcode,
            requiredHTTPHeaders: requiredHTTPHeaders ?? [:],
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            videoWidth: videoStream?.width,
            videoHeight: videoStream?.height,
            videoFrameRate: videoStream?.realFrameRate
        )
    }

    private func preferredAppleAudioCodec(explicit: String?, fallback: String?) -> String? {
        if let explicit {
            let lowered = explicit.lowercased()
            if lowered.contains("truehd"), let fallback {
                // Prefer E-AC-3/AC-3/AAC whenever available for Apple native pipeline stability.
                return fallback
            }
            return explicit
        }
        return fallback
    }

    private func preferredAppleAudioStream(from audioStreams: [MediaStreamDTO]) -> MediaStreamDTO? {
        func rank(_ stream: MediaStreamDTO) -> Int {
            let codec = (stream.codec ?? "").lowercased()
            var score = 0
            if codec.contains("eac3") || codec.contains("ec3") {
                score += 10_000
            } else if codec.contains("ac3") {
                score += 8_000
            } else if codec.contains("aac") {
                score += 7_000
            } else if codec.contains("truehd") {
                score += 500
            }
            if stream.isDefault == true {
                score += 1_000
            }
            if let channels = stream.channels {
                score += min(channels, 12) * 10
            }
            return score
        }

        return audioStreams.max { lhs, rhs in
            rank(lhs) < rank(rhs)
        }
    }

    private func resolvePlaybackURL(_ value: String, serverURL: URL) -> URL? {
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }

        let parts = value.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let relativePath = parts.first.map(String.init) ?? ""

        var resolved = serverURL
        let normalizedPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !normalizedPath.isEmpty {
            resolved = serverURL.appendingPathComponent(normalizedPath)
        }

        guard parts.count == 2 else {
            return resolved
        }

        var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = String(parts[1])
        return components?.url
    }
}

struct MediaStreamDTO: Decodable {
    // OpenAPI source:
    // /Users/florian/Downloads/jellyfin-openapi-stable.json
    // $.components.schemas.MediaStream
    let index: Int?
    let type: String?
    let title: String?
    let displayTitle: String?
    let language: String?
    let isDefault: Bool?
    let isForced: Bool?
    let codec: String?
    let profile: String?
    let bitDepth: Int?
    let colorRange: String?
    let colorSpace: String?
    let colorTransfer: String?
    let colorPrimaries: String?
    let dvVersionMajor: Int?
    let dvVersionMinor: Int?
    let dvProfile: Int?
    let dvLevel: Int?
    let rpuPresentFlag: Bool?
    let elPresentFlag: Bool?
    let blPresentFlag: Bool?
    let dvBlSignalCompatibilityId: Int?
    let hdr10PlusPresentFlag: Bool?
    let videoRange: String?
    let videoRangeType: String?
    let videoDoViTitle: String?
    let channels: Int?
    let channelLayout: String?
    let bitrate: Int?
    let width: Int?
    let height: Int?
    let realFrameRate: Double?

    init(
        index: Int?,
        type: String?,
        title: String?,
        displayTitle: String?,
        language: String?,
        isDefault: Bool?,
        isForced: Bool? = nil,
        codec: String?,
        profile: String?,
        bitDepth: Int?,
        colorRange: String? = nil,
        colorSpace: String? = nil,
        colorTransfer: String? = nil,
        colorPrimaries: String? = nil,
        dvVersionMajor: Int? = nil,
        dvVersionMinor: Int? = nil,
        dvProfile: Int? = nil,
        dvLevel: Int? = nil,
        rpuPresentFlag: Bool? = nil,
        elPresentFlag: Bool? = nil,
        blPresentFlag: Bool? = nil,
        dvBlSignalCompatibilityId: Int? = nil,
        hdr10PlusPresentFlag: Bool? = nil,
        videoRange: String? = nil,
        videoRangeType: String?,
        videoDoViTitle: String? = nil,
        channels: Int?,
        channelLayout: String?,
        bitrate: Int?,
        width: Int?,
        height: Int?,
        realFrameRate: Double? = nil
    ) {
        self.index = index
        self.type = type
        self.title = title
        self.displayTitle = displayTitle
        self.language = language
        self.isDefault = isDefault
        self.isForced = isForced
        self.codec = codec
        self.profile = profile
        self.bitDepth = bitDepth
        self.colorRange = colorRange
        self.colorSpace = colorSpace
        self.colorTransfer = colorTransfer
        self.colorPrimaries = colorPrimaries
        self.dvVersionMajor = dvVersionMajor
        self.dvVersionMinor = dvVersionMinor
        self.dvProfile = dvProfile
        self.dvLevel = dvLevel
        self.rpuPresentFlag = rpuPresentFlag
        self.elPresentFlag = elPresentFlag
        self.blPresentFlag = blPresentFlag
        self.dvBlSignalCompatibilityId = dvBlSignalCompatibilityId
        self.hdr10PlusPresentFlag = hdr10PlusPresentFlag
        self.videoRange = videoRange
        self.videoRangeType = videoRangeType
        self.videoDoViTitle = videoDoViTitle
        self.channels = channels
        self.channelLayout = channelLayout
        self.bitrate = bitrate
        self.width = width
        self.height = height
        self.realFrameRate = realFrameRate
    }

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case title = "Title"
        case displayTitle = "DisplayTitle"
        case language = "Language"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case codec = "Codec"
        case profile = "Profile"
        case bitDepth = "BitDepth"
        case colorRange = "ColorRange"
        case colorSpace = "ColorSpace"
        case colorTransfer = "ColorTransfer"
        case colorPrimaries = "ColorPrimaries"
        case dvVersionMajor = "DvVersionMajor"
        case dvVersionMinor = "DvVersionMinor"
        case dvProfile = "DvProfile"
        case dvLevel = "DvLevel"
        case rpuPresentFlag = "RpuPresentFlag"
        case elPresentFlag = "ElPresentFlag"
        case blPresentFlag = "BlPresentFlag"
        case dvBlSignalCompatibilityId = "DvBlSignalCompatibilityId"
        case hdr10PlusPresentFlag = "Hdr10PlusPresentFlag"
        case videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType"
        case videoDoViTitle = "VideoDoViTitle"
        case channels = "Channels"
        case channelLayout = "ChannelLayout"
        case bitrate = "BitRate"
        case width = "Width"
        case height = "Height"
        case realFrameRate = "RealFrameRate"
    }

    /// Jellyfin sends some Bool fields as integers (0/1) instead of true/false.
    /// This helper tries Bool first, then falls back to Int interpretation.
    private static func flexibleBool(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return intValue != 0
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        isDefault = Self.flexibleBool(from: container, forKey: .isDefault)
        isForced = Self.flexibleBool(from: container, forKey: .isForced)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        bitDepth = try container.decodeIfPresent(Int.self, forKey: .bitDepth)
        colorRange = try container.decodeIfPresent(String.self, forKey: .colorRange)
        colorSpace = try container.decodeIfPresent(String.self, forKey: .colorSpace)
        colorTransfer = try container.decodeIfPresent(String.self, forKey: .colorTransfer)
        colorPrimaries = try container.decodeIfPresent(String.self, forKey: .colorPrimaries)
        dvVersionMajor = try container.decodeIfPresent(Int.self, forKey: .dvVersionMajor)
        dvVersionMinor = try container.decodeIfPresent(Int.self, forKey: .dvVersionMinor)
        dvProfile = try container.decodeIfPresent(Int.self, forKey: .dvProfile)
        dvLevel = try container.decodeIfPresent(Int.self, forKey: .dvLevel)
        rpuPresentFlag = Self.flexibleBool(from: container, forKey: .rpuPresentFlag)
        elPresentFlag = Self.flexibleBool(from: container, forKey: .elPresentFlag)
        blPresentFlag = Self.flexibleBool(from: container, forKey: .blPresentFlag)
        dvBlSignalCompatibilityId = try container.decodeIfPresent(Int.self, forKey: .dvBlSignalCompatibilityId)
        hdr10PlusPresentFlag = Self.flexibleBool(from: container, forKey: .hdr10PlusPresentFlag)
        videoRange = try container.decodeIfPresent(String.self, forKey: .videoRange)
        videoRangeType = try container.decodeIfPresent(String.self, forKey: .videoRangeType)
        videoDoViTitle = try container.decodeIfPresent(String.self, forKey: .videoDoViTitle)
        channels = try container.decodeIfPresent(Int.self, forKey: .channels)
        channelLayout = try container.decodeIfPresent(String.self, forKey: .channelLayout)
        bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        realFrameRate = try container.decodeIfPresent(Double.self, forKey: .realFrameRate)
    }

    func toTrack(streamCodec: String?) -> MediaTrack {
        let trackIndex = index ?? 0
        return MediaTrack(
            id: "track-\(trackIndex)",
            title: displayTitle ?? title ?? "Track \(trackIndex + 1)",
            language: language,
            codec: streamCodec ?? codec,
            isDefault: isDefault ?? false,
            isForced: isForced ?? false,
            index: trackIndex
        )
    }
}

struct PlaybackInfoRequestDTO: Encodable {
    // OpenAPI source:
    // /Users/florian/Downloads/jellyfin-openapi-stable.json
    // $.components.schemas.PlaybackInfoDto
    let userID: String?
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool
    let maxStreamingBitrate: Int?
    let startTimeTicks: Int64?
    let allowVideoStreamCopy: Bool?
    let allowAudioStreamCopy: Bool?
    let maxAudioChannels: Int?
    let deviceProfile: DeviceProfileRequestDTO?

    enum CodingKeys: String, CodingKey {
        case userID = "UserId"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case startTimeTicks = "StartTimeTicks"
        case allowVideoStreamCopy = "AllowVideoStreamCopy"
        case allowAudioStreamCopy = "AllowAudioStreamCopy"
        case maxAudioChannels = "MaxAudioChannels"
        case deviceProfile = "DeviceProfile"
    }
}

enum DlnaProfileTypeDTO: Int, Encodable {
    case audio = 0
    case video = 1
    case photo = 2
    case subtitle = 3
    case lyric = 4
}

enum MediaStreamProtocolDTO: Int, Encodable {
    case http = 0
    case hls = 1
}

enum EncodingContextDTO: Int, Encodable {
    case streaming = 0
    case staticMode = 1
}

enum SubtitleDeliveryMethodDTO: Int, Encodable {
    case encode = 0
    case embed = 1
    case external = 2
    case hls = 3
    case drop = 4
}

struct DeviceProfileRequestDTO: Encodable {
    let name: String
    let id: String
    let maxStreamingBitrate: Int
    let musicStreamingTranscodingBitrate: Int
    let directPlayProfiles: [DirectPlayProfileRequestDTO]
    let transcodingProfiles: [TranscodingProfileRequestDTO]
    let subtitleProfiles: [SubtitleProfileRequestDTO]
    let responseProfiles: [ResponseProfileRequestDTO]?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case musicStreamingTranscodingBitrate = "MusicStreamingTranscodingBitrate"
        case directPlayProfiles = "DirectPlayProfiles"
        case transcodingProfiles = "TranscodingProfiles"
        case subtitleProfiles = "SubtitleProfiles"
        case responseProfiles = "ResponseProfiles"
    }

    static func iosCompatibilityH264(maxStreamingBitrate: Int, maxAudioChannels: Int) -> DeviceProfileRequestDTO {
        DeviceProfileRequestDTO(
            name: "ReelFin iOS H264",
            id: "5f9f5b0d-4e24-4c24-96e9-4d9eb7221d2e",
            maxStreamingBitrate: maxStreamingBitrate,
            musicStreamingTranscodingBitrate: 192_000,
            directPlayProfiles: [
                DirectPlayProfileRequestDTO(
                    container: "mp4,m4v,mov,mkv",
                    audioCodec: "aac,ac3,eac3,mp3,alac",
                    videoCodec: "h264,avc1",
                    type: .video
                )
            ],
            transcodingProfiles: [
                TranscodingProfileRequestDTO(
                    container: "ts",
                    type: .video,
                    videoCodec: "h264",
                    audioCodec: "aac",
                    protocolValue: .hls,
                    context: .streaming,
                    maxAudioChannels: String(maxAudioChannels),
                    enableSubtitlesInManifest: false,
                    estimateContentLength: false,
                    copyTimestamps: false,
                    enableAudioVbrEncoding: true
                )
            ],
            subtitleProfiles: [
                SubtitleProfileRequestDTO(
                    format: "srt",
                    method: .external
                ),
                SubtitleProfileRequestDTO(
                    format: "vtt",
                    method: .external
                )
            ],
            responseProfiles: [
                ResponseProfileRequestDTO(
                    type: .video,
                    container: "m4v",
                    mimeType: "video/mp4"
                )
            ]
        )
    }

    static func iosOptimizedHEVC(maxStreamingBitrate: Int, maxAudioChannels: Int) -> DeviceProfileRequestDTO {
        DeviceProfileRequestDTO(
            name: "ReelFin Apple Optimized (DV/HDR/Atmos)",
            id: "7d0410cb-260f-4f7c-82cb-0d3ed7a5de38",
            maxStreamingBitrate: maxStreamingBitrate,
            musicStreamingTranscodingBitrate: 192_000,
            directPlayProfiles: [
                DirectPlayProfileRequestDTO(
                    container: "mp4,m4v,mov,mkv",
                    audioCodec: "aac,ac3,eac3,mp3,alac,flac",
                    videoCodec: "hevc,h265,hvc1,dvh1,dvhe,h264,avc1",
                    type: .video
                )
            ],
            transcodingProfiles: [
                TranscodingProfileRequestDTO(
                    container: "fmp4",
                    type: .video,
                    videoCodec: "hevc",
                    audioCodec: "eac3,aac",
                    protocolValue: .hls,
                    context: .streaming,
                    maxAudioChannels: String(maxAudioChannels),
                    enableSubtitlesInManifest: false,
                    estimateContentLength: false,
                    copyTimestamps: false,
                    enableAudioVbrEncoding: true
                )
            ],
            subtitleProfiles: [
                SubtitleProfileRequestDTO(
                    format: "srt",
                    method: .external
                ),
                SubtitleProfileRequestDTO(
                    format: "vtt",
                    method: .external
                )
            ],
            responseProfiles: [
                ResponseProfileRequestDTO(
                    type: .video,
                    container: "mp4,m4v",
                    mimeType: "video/mp4"
                )
            ]
        )
    }

    /// tvOS-optimized profile for Apple TV 4K.
    /// DirectPlay: mp4/m4v/mov with H.264/HEVC/DV + AAC/AC3/EAC3/ALAC/FLAC.
    /// Jellyfin will use DirectStream (remux) for MKV with compatible codecs.
    /// Transcode: HLS fMP4 HEVC + EAC3/AAC for incompatible sources.
    static func tvOSOptimized(maxStreamingBitrate: Int, maxAudioChannels: Int) -> DeviceProfileRequestDTO {
        DeviceProfileRequestDTO(
            name: "ReelFin tvOS Apple TV (DV/HDR/Atmos)",
            id: "a3c1f8e2-7b5d-4a9e-b6c0-d2e4f8a1b3c5",
            maxStreamingBitrate: maxStreamingBitrate,
            musicStreamingTranscodingBitrate: 192_000,
            directPlayProfiles: [
                // MP4-family: full codec support
                DirectPlayProfileRequestDTO(
                    container: "mp4,m4v,mov",
                    audioCodec: "aac,ac3,eac3,mp3,alac,flac",
                    videoCodec: "hevc,h265,hvc1,dvh1,dvhe,h264,avc1",
                    type: .video
                ),
                // MPEG-TS: H.264/HEVC with common audio
                DirectPlayProfileRequestDTO(
                    container: "mpegts",
                    audioCodec: "aac,ac3,eac3",
                    videoCodec: "hevc,h264",
                    type: .video
                )
            ],
            transcodingProfiles: [
                // Server-side transcode: HLS TS with H.264 video.
                // Jellyfin does not produce real fMP4 segments (serves TS bytes
                // despite SegmentContainer=fmp4), so HEVC fMP4 HLS is broken.
                // H264 TS is the only reliable transcode path on tvOS.
                TranscodingProfileRequestDTO(
                    container: "ts",
                    type: .video,
                    videoCodec: "h264",
                    audioCodec: "aac,ac3,eac3",
                    protocolValue: .hls,
                    context: .streaming,
                    maxAudioChannels: String(maxAudioChannels),
                    enableSubtitlesInManifest: false,
                    estimateContentLength: false,
                    copyTimestamps: true,
                    enableAudioVbrEncoding: true
                )
            ],
            subtitleProfiles: [
                SubtitleProfileRequestDTO(
                    format: "srt",
                    method: .external
                ),
                SubtitleProfileRequestDTO(
                    format: "vtt",
                    method: .external
                ),
                SubtitleProfileRequestDTO(
                    format: "ass",
                    method: .external
                ),
                SubtitleProfileRequestDTO(
                    format: "ssa",
                    method: .external
                )
            ],
            responseProfiles: [
                ResponseProfileRequestDTO(
                    type: .video,
                    container: "m4v",
                    mimeType: "video/mp4"
                )
            ]
        )
    }

    /// Conservative tvOS Simulator profile.
    /// Startup timings on simulator are not representative of Apple TV hardware,
    /// so this profile prefers the lowest-risk H.264 + AAC path.
    static func tvOSSimulatorCompatibilityH264(maxStreamingBitrate: Int, maxAudioChannels: Int) -> DeviceProfileRequestDTO {
        DeviceProfileRequestDTO(
            name: "ReelFin tvOS Simulator H264",
            id: "3b1168e1-0d4c-4d70-a5b6-91f8b4fb7c8d",
            maxStreamingBitrate: maxStreamingBitrate,
            musicStreamingTranscodingBitrate: 192_000,
            directPlayProfiles: [
                DirectPlayProfileRequestDTO(
                    container: "mp4,m4v,mov",
                    audioCodec: "aac",
                    videoCodec: "h264,avc1",
                    type: .video
                )
            ],
            transcodingProfiles: [
                TranscodingProfileRequestDTO(
                    container: "ts",
                    type: .video,
                    videoCodec: "h264",
                    audioCodec: "aac",
                    protocolValue: .hls,
                    context: .streaming,
                    maxAudioChannels: String(maxAudioChannels),
                    enableSubtitlesInManifest: false,
                    estimateContentLength: false,
                    copyTimestamps: true,
                    enableAudioVbrEncoding: true
                )
            ],
            subtitleProfiles: [
                SubtitleProfileRequestDTO(
                    format: "srt",
                    method: .external
                ),
                SubtitleProfileRequestDTO(
                    format: "vtt",
                    method: .external
                )
            ],
            responseProfiles: [
                ResponseProfileRequestDTO(
                    type: .video,
                    container: "m4v",
                    mimeType: "video/mp4"
                )
            ]
        )
    }
}

struct DirectPlayProfileRequestDTO: Encodable {
    let container: String
    let audioCodec: String?
    let videoCodec: String?
    let type: DlnaProfileTypeDTO

    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case audioCodec = "AudioCodec"
        case videoCodec = "VideoCodec"
        case type = "Type"
    }
}

struct TranscodingProfileRequestDTO: Encodable {
    let container: String
    let type: DlnaProfileTypeDTO
    let videoCodec: String
    let audioCodec: String
    let protocolValue: MediaStreamProtocolDTO
    let context: EncodingContextDTO
    let maxAudioChannels: String
    let enableSubtitlesInManifest: Bool
    let estimateContentLength: Bool
    let copyTimestamps: Bool
    let enableAudioVbrEncoding: Bool

    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case type = "Type"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
        case protocolValue = "Protocol"
        case context = "Context"
        case maxAudioChannels = "MaxAudioChannels"
        case enableSubtitlesInManifest = "EnableSubtitlesInManifest"
        case estimateContentLength = "EstimateContentLength"
        case copyTimestamps = "CopyTimestamps"
        case enableAudioVbrEncoding = "EnableAudioVbrEncoding"
    }
}

struct SubtitleProfileRequestDTO: Encodable {
    let format: String
    let method: SubtitleDeliveryMethodDTO

    enum CodingKeys: String, CodingKey {
        case format = "Format"
        case method = "Method"
    }
}

struct ResponseProfileRequestDTO: Encodable {
    let type: DlnaProfileTypeDTO
    let container: String
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case container = "Container"
        case mimeType = "MimeType"
    }
}

struct PlaybackProgressRequestDTO: Encodable {
    let itemID: String
    let positionTicks: Int64
    let canSeek: Bool
    let isPaused: Bool
    let isMuted: Bool
    let playMethod: String

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case positionTicks = "PositionTicks"
        case canSeek = "CanSeek"
        case isPaused = "IsPaused"
        case isMuted = "IsMuted"
        case playMethod = "PlayMethod"
    }
}

// MARK: - Quick Connect DTOs

struct QuickConnectInitiateResponseDTO: Decodable {
    /// Short code displayed to the user (e.g. "A1B2").
    let code: String
    /// Opaque secret used to poll for auth completion.
    let secret: String
    /// Whether the request was successfully initiated.
    let authenticated: Bool

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case secret = "Secret"
        case authenticated = "Authenticated"
    }
}

struct QuickConnectAuthRequestDTO: Encodable {
    let secret: String

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
    }
}

struct QuickConnectAuthResponseDTO: Decodable {
    /// True when the user has approved the code on another device.
    let authenticated: Bool

    enum CodingKeys: String, CodingKey {
        case authenticated = "Authenticated"
    }
}

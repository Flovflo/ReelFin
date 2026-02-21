import Foundation
import Shared

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
    let people: [PersonDTO]?

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
        case people = "People"
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
            parentID: parentID ?? seriesID
        )
    }
}

struct PersonDTO: Decodable {
    let id: String
    let name: String
    let role: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case role = "Role"
    }

    func toDomain() -> PersonCredit {
        PersonCredit(id: id, name: name, role: role)
    }
}

struct PlaybackInfoResponseDTO: Decodable {
    let mediaSources: [MediaSourceDTO]

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
    }
}

struct MediaSourceDTO: Decodable {
    let id: String
    let name: String?
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
        let audioTracks = tracks.filter { $0.type?.lowercased() == "audio" }.map { $0.toTrack() }
        let subtitleTracks = tracks.filter { $0.type?.lowercased() == "subtitle" }.map { $0.toTrack() }
        let videoStream = tracks.first(where: { $0.type?.lowercased() == "video" })
        let audioStream = tracks.first(where: { $0.type?.lowercased() == "audio" })

        let streamURL = directStreamURL.flatMap { resolvePlaybackURL($0, serverURL: serverURL) }
        let transcode = transcodingURL.flatMap { resolvePlaybackURL($0, serverURL: serverURL) }

        return MediaSource(
            id: id,
            itemID: itemID,
            name: name ?? "Source",
            container: container,
            videoCodec: videoCodec ?? videoStream?.codec,
            audioCodec: audioCodec ?? audioStream?.codec,
            bitrate: bitrate ?? videoStream?.bitrate,
            videoBitDepth: videoBitDepth ?? videoStream?.bitDepth,
            videoRange: videoRangeType ?? videoStream?.videoRangeType,
            videoProfile: videoStream?.profile,
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
            subtitleTracks: subtitleTracks
        )
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
    let index: Int?
    let type: String?
    let title: String?
    let displayTitle: String?
    let language: String?
    let isDefault: Bool?
    let codec: String?
    let profile: String?
    let bitDepth: Int?
    let videoRangeType: String?
    let channels: Int?
    let channelLayout: String?
    let bitrate: Int?

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case title = "Title"
        case displayTitle = "DisplayTitle"
        case language = "Language"
        case isDefault = "IsDefault"
        case codec = "Codec"
        case profile = "Profile"
        case bitDepth = "BitDepth"
        case videoRangeType = "VideoRangeType"
        case channels = "Channels"
        case channelLayout = "ChannelLayout"
        case bitrate = "BitRate"
    }

    func toTrack() -> MediaTrack {
        let trackIndex = index ?? 0
        return MediaTrack(
            id: "track-\(trackIndex)",
            title: displayTitle ?? title ?? "Track \(trackIndex + 1)",
            language: language,
            isDefault: isDefault ?? false,
            index: trackIndex
        )
    }
}

struct PlaybackInfoRequestDTO: Encodable {
    let userID: String?
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool
    let maxStreamingBitrate: Int?
    let startTimeTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case userID = "UserId"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case startTimeTicks = "StartTimeTicks"
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

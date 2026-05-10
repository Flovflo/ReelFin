import PlaybackEngine
import Shared

func makeGuaranteeSource(
    container: String = "mp4",
    videoCodec: String = "hevc",
    audioCodec: String = "eac3",
    videoRangeType: String? = nil,
    dvProfile: Int? = nil,
    dvBlSignalCompatibilityId: Int? = nil,
    videoWidth: Int = 3840,
    videoHeight: Int = 2160
) -> MediaSource {
    MediaSource(
        id: "source",
        itemID: "item",
        name: "Source",
        container: container,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
        bitrate: 80_000_000,
        videoBitDepth: 10,
        videoRangeType: videoRangeType,
        dvProfile: dvProfile,
        dvBlSignalCompatibilityId: dvBlSignalCompatibilityId,
        supportsDirectPlay: true,
        supportsDirectStream: true,
        videoWidth: videoWidth,
        videoHeight: videoHeight
    )
}

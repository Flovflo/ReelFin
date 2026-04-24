import Foundation

public enum MatroskaCodecMapper {
    public static func normalizedCodec(_ codecID: String) -> String {
        switch codecID.uppercased() {
        case "V_MPEG4/ISO/AVC": return "h264"
        case "V_MPEGH/ISO/HEVC": return "hevc"
        case "V_AV1": return "av1"
        case "V_VP9": return "vp9"
        case "V_MPEG2": return "mpeg2"
        case "V_MS/VFW/FOURCC": return "vfw"
        case "A_AAC",
             "A_AAC/MPEG2/MAIN",
             "A_AAC/MPEG4/MAIN",
             "A_AAC/MPEG2/LC",
             "A_AAC/MPEG4/LC",
             "A_AAC/MPEG2/SSR",
             "A_AAC/MPEG4/SSR",
             "A_AAC/MPEG4/LTP",
             "A_AAC/MPEG2/LC/SBR",
             "A_AAC/MPEG4/LC/SBR",
             "A_AAC/MPEG4/",
             "A_AAC/MPEG2/": return "aac"
        case "A_AC3": return "ac3"
        case "A_EAC3": return "eac3"
        case "A_TRUEHD": return "truehd"
        case "A_DTS": return "dts"
        case "A_FLAC": return "flac"
        case "A_OPUS": return "opus"
        case "A_VORBIS": return "vorbis"
        case "A_PCM/INT/LIT", "A_PCM/INT/BIG", "A_PCM/FLOAT/IEEE": return "pcm"
        case "S_TEXT/UTF8": return "srt"
        case "S_TEXT/WEBVTT": return "webvtt"
        case "S_TEXT/ASS": return "ass"
        case "S_TEXT/SSA": return "ssa"
        case "S_HDMV/PGS": return "pgs"
        case "S_VOBSUB": return "vobsub"
        default: return codecID.lowercased()
        }
    }

    public static func subtitleFormat(_ codecID: String) -> SubtitleFormat {
        switch normalizedCodec(codecID) {
        case "srt": return .srt
        case "webvtt": return .webVTT
        case "ass": return .ass
        case "ssa": return .ssa
        case "pgs": return .pgs
        case "vobsub": return .vobSub
        default: return .unknown
        }
    }
}

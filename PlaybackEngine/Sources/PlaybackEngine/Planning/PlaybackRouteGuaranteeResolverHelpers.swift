import Foundation
import Shared

func appleDirectDVEvidence(source: MediaSource, finalURLQuery: [String: String]) -> Bool {
    let codec = source.normalizedVideoCodec
    let container = source.normalizedContainer
    let appleContainer = container == "mp4" || container == "m4v" || container == "mov"
    return appleContainer
        && (codec.contains("dvh1")
            || codec.contains("dvhe")
            || source.dvProfile == 5
            || finalURLQuery["videocodec"]?.contains("dvh") == true)
}

func routeLabel(route: PlaybackRoute, startupClass: PlaybackStartupClass) -> String {
    switch (route, startupClass) {
    case (.directPlay, _): return "AVKit Direct Original"
    case (.remux, .hlsRemux), (.transcode, .hlsRemux): return "AVKit HLS fMP4 Remux"
    case (.remux, _), (.transcode, .progressiveRemux): return "AVKit Progressive Remux"
    case (.nativeBridge, _): return "Native Direct Original"
    case (.transcode, _): return "HLS Video Transcode"
    }
}

func isLoopback(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
}

func isPrivateLAN(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host.hasPrefix("10.")
        || host.hasPrefix("192.168.")
        || host.range(of: #"^172\.(1[6-9]|2[0-9]|3[0-1])\."#, options: .regularExpression) != nil
        || host.hasSuffix(".local")
}

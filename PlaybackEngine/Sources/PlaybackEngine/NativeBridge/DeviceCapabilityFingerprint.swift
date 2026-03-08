import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Accurately models what the current device can decode, render, and output
/// so the decision engine avoids unnecessary transcodes.
public struct DeviceCapabilityFingerprint: Sendable {

    // MARK: - Video Codec Support

    public let supportsHEVC: Bool
    public let supportsHEVCMain10: Bool
    public let supportsH264: Bool
    public let supportsAV1: Bool
    public let supportsDolbyVision: Bool    // Best-effort detection; not guaranteed
    public let supportsHDR10: Bool
    public let supportsHLG: Bool

    // MARK: - Audio Codec Support

    public let supportsAAC: Bool
    public let supportsAC3: Bool
    public let supportsEAC3: Bool
    public let supportsAtmos: Bool          // E-AC-3 JOC on supported hardware
    public let supportsFLAC: Bool
    public let supportsALAC: Bool
    public let supportsOpus: Bool

    // MARK: - Container Support (AVPlayer native)

    public let nativeContainers: Set<String>  // mp4, m4v, mov, m4a
    public let hlsSupported: Bool

    // MARK: - Device Info

    public let modelIdentifier: String
    public let osVersion: String
    public let chipGeneration: ChipGeneration

    public enum ChipGeneration: String, Sendable, Comparable {
        case a11OrOlder = "A11-"
        case a12       = "A12"
        case a13       = "A13"
        case a14       = "A14"
        case a15       = "A15"
        case a16       = "A16"
        case a17Pro    = "A17Pro"
        case a18       = "A18"
        case m1        = "M1"
        case m2        = "M2"
        case m3        = "M3"
        case m4        = "M4"
        case unknown   = "Unknown"

        public static func < (lhs: ChipGeneration, rhs: ChipGeneration) -> Bool {
            let order: [ChipGeneration] = [
                .a11OrOlder, .a12, .a13, .a14, .a15, .a16, .a17Pro, .a18,
                .m1, .m2, .m3, .m4
            ]
            let li = order.firstIndex(of: lhs) ?? 0
            let ri = order.firstIndex(of: rhs) ?? 0
            return li < ri
        }
    }

    // MARK: - Factory

    /// Build a fingerprint for the current device at runtime.
    public static func current() -> DeviceCapabilityFingerprint {
        let osVer = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(osVer.majorVersion).\(osVer.minorVersion).\(osVer.patchVersion)"
        let model = machineIdentifier()
        let chip = classifyChip(model: model)

        // HEVC: supported on A9+ (iPhone 6s+), always on tvOS  
        let hevc = chip >= .a11OrOlder || osVer.majorVersion >= 11
        let hevcMain10 = hevc && chip >= .a11OrOlder
        let av1 = chip >= .a17Pro || chip >= .m3

        // HDR: requires A11+ for HDR10, A12+ for Dolby Vision on iPhone.
        // Simulator reports modern model identifiers but cannot be trusted for DV decode/render behavior.
        let hdr10 = chip >= .a11OrOlder
        #if targetEnvironment(simulator)
        let dolbyVision = false
        #else
        let dolbyVision = chip >= .a12
        #endif
        let hlg = chip >= .a11OrOlder

        // Audio: AC-3/E-AC-3 universally supported on iOS/tvOS via AVPlayer passthrough
        // Atmos (E-AC-3 JOC): requires compatible hardware (AirPods Pro, HomePod, etc.)
        let atmos = chip >= .a12  // The chip can decode; actual output depends on audio route

        return DeviceCapabilityFingerprint(
            supportsHEVC: hevc,
            supportsHEVCMain10: hevcMain10,
            supportsH264: true,
            supportsAV1: av1,
            supportsDolbyVision: dolbyVision,
            supportsHDR10: hdr10,
            supportsHLG: hlg,
            supportsAAC: true,
            supportsAC3: true,
            supportsEAC3: true,
            supportsAtmos: atmos,
            supportsFLAC: true,
            supportsALAC: true,
            supportsOpus: osVer.majorVersion >= 16,
            nativeContainers: ["mp4", "m4v", "mov", "m4a", "caf"],
            hlsSupported: true,
            modelIdentifier: model,
            osVersion: osString,
            chipGeneration: chip
        )
    }

    /// Check if a specific video track can be hardware-decoded on this device.
    public func canHardwareDecode(videoTrack: TrackInfo) -> Bool {
        let codec = videoTrack.codecName.lowercased()
        if codec.contains("hevc") || codec.contains("h265") || codec.contains("hvc1") || codec.contains("hev1") {
            if (videoTrack.bitDepth ?? 8) >= 10 {
                return supportsHEVCMain10
            }
            return supportsHEVC
        }
        if codec.contains("h264") || codec.contains("avc") {
            return supportsH264
        }
        if codec.contains("av1") || codec.contains("av01") {
            return supportsAV1
        }
        if codec.contains("dvh1") || codec.contains("dvhe") {
            return supportsDolbyVision
        }
        return false
    }

    /// Check if an audio codec is natively supported (can be passed through to AVPlayer).
    public func canPassthroughAudio(audioTrack: TrackInfo) -> Bool {
        let support = audioTrack.audioSupport ?? AudioCodecSupport.classify(audioTrack.codecName)
        return support == .native
    }

    /// Determine the best HDR output mode for a video track on this device.
    public func bestHDRMode(for track: TrackInfo) -> String {
        let codec = track.codecName.lowercased()
        let isDV = codec.contains("dvh1") || codec.contains("dvhe")
        let transfer = track.transferCharacteristic ?? 0
        let primaries = track.colourPrimaries ?? 0

        if isDV && supportsDolbyVision {
            return "DolbyVision (best-effort)"
        }
        // PQ transfer + BT.2020 primaries = HDR10
        if transfer == 16 && primaries == 9 && supportsHDR10 {
            return "HDR10"
        }
        // HLG
        if transfer == 18 && supportsHLG {
            return "HLG"
        }
        if (track.bitDepth ?? 8) >= 10 && primaries == 9 && supportsHDR10 {
            return "HDR10"
        }
        return "SDR"
    }

    // MARK: - Private Helpers

    private static func machineIdentifier() -> String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
        #endif
    }

    private static func classifyChip(model: String) -> ChipGeneration {
        // iPhone identifiers: iPhoneXX,Y
        // iPad identifiers: iPadXX,Y
        // AppleTV identifiers: AppleTVX,Y
        let lower = model.lowercased()

        // M-series (iPad Pro / Mac)
        if lower.contains("ipad14") || lower.contains("ipad16") { return .m2 }
        if lower.contains("ipad13") { return .m1 }

        // iPhone chip mapping (simplified)
        if lower.hasPrefix("iphone17") { return .a18 }
        if lower.hasPrefix("iphone16") { return .a17Pro }
        if lower.hasPrefix("iphone15") { return .a16 }
        if lower.hasPrefix("iphone14") { return .a15 }
        if lower.hasPrefix("iphone13") { return .a14 }
        if lower.hasPrefix("iphone12") { return .a13 }
        if lower.hasPrefix("iphone11") { return .a12 }

        // Apple TV
        if lower.hasPrefix("appletv") {
            // Apple TV 4K 2nd gen+ has A12+
            if lower.contains("appletv14") || lower.contains("appletv11,1") { return .a15 }
            if lower.contains("appletv11") { return .a12 }
            return .a11OrOlder
        }

        if lower.contains("simulator") { return .a15 }

        return .unknown
    }
}

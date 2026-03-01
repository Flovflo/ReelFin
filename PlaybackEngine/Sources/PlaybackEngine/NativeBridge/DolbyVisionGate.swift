import Foundation

public enum DolbyVisionGateDecision: Sendable, Equatable {
    case enableDV(profile: Int, level: Int, compatId: Int)
    case disableDV(reason: String)

    public var isEnabled: Bool {
        if case .enableDV = self { return true }
        return false
    }
}

public enum DolbyVisionGate {
    public static func evaluate(plan: NativeBridgePlan, streamInfo: StreamInfo, device: DeviceCapabilityFingerprint) -> DolbyVisionGateDecision {
        let videoTrack = streamInfo.primaryVideoTrack ?? plan.videoTrack

        guard device.supportsDolbyVision else {
            return .disableDV(reason: "device_no_dolby_vision")
        }

        guard videoTrack.codecName.lowercased().contains("hevc") || videoTrack.codecID.lowercased().contains("hevc") else {
            return .disableDV(reason: "non_hevc_video")
        }

        guard (videoTrack.bitDepth ?? 8) >= 10 else {
            return .disableDV(reason: "bit_depth_below_10")
        }

        // Check for DV profile — this is the strongest signal
        guard let dvProfile = plan.dvProfile else {
            return .disableDV(reason: "missing_dv_profile")
        }
        guard dvProfile == 5 || dvProfile == 7 || dvProfile == 8 else {
            return .disableDV(reason: "unsupported_dv_profile_\(dvProfile)")
        }

        // For Profile 8 (single-layer, HDR10-compatible BL), relaxed checks:
        // - videoRangeType may not be set for MKV sources going through NativeBridge
        // - BT.2020/PQ may not be set in Colour element for all MKV muxers
        // Trust the DV profile from the API/plan as the primary signal.
        let rangeType = (plan.videoRangeType ?? "").lowercased()
        if dvProfile == 8 {
            // Profile 8 can work with HDR10 base layer; accept broader range types
            let acceptableRanges = ["doviwithhdr10", "dovi", "hdr10", ""]
            if !acceptableRanges.contains(rangeType) {
                return .disableDV(reason: "video_range_type_incompatible_\(rangeType)")
            }
        } else {
            // Stricter check for other profiles
            guard videoTrack.colourPrimaries == 9, videoTrack.transferCharacteristic == 16 else {
                return .disableDV(reason: "missing_bt2020_pq")
            }
            guard rangeType.contains("dovi") else {
                return .disableDV(reason: "video_range_type_not_dovi")
            }
        }

        let level = plan.dvLevel ?? 6
        let compatId = plan.dvBlSignalCompatibilityId ?? 1
        return .enableDV(profile: dvProfile, level: level, compatId: compatId)
    }
}

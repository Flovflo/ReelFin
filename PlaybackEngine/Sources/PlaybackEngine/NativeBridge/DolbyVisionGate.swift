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
    // Test-only override. `nil` means runtime policy.
    static var experimentalDVPackagingOverride: Bool?
    // Runtime override used by app playback logic (for example DV titles).
    static var runtimeDVPackagingOverride: Bool?

    public static func evaluate(plan: NativeBridgePlan, streamInfo: StreamInfo, device: DeviceCapabilityFingerprint) -> DolbyVisionGateDecision {
        let videoTrack = selectedVideoTrack(plan: plan, streamInfo: streamInfo)

        guard isExperimentalDVPackagingEnabled() else {
            return .disableDV(reason: "experimental_dv_packaging_disabled")
        }

        guard device.supportsDolbyVision else {
            return .disableDV(reason: "device_no_dolby_vision")
        }

        guard HEVCCodecFamily.contains(videoTrack) else {
            return .disableDV(reason: "non_hevc_video")
        }

        let metadataBitDepth = videoTrack.bitDepth
        let hvccBitDepth = inferHEVCBitDepth(from: videoTrack.codecPrivate)
        let effectiveBitDepth = max(metadataBitDepth ?? 0, hvccBitDepth ?? 0)
        guard effectiveBitDepth >= 10 else {
            let metadataLabel = metadataBitDepth.map(String.init) ?? "nil"
            let hvccLabel = hvccBitDepth.map(String.init) ?? "nil"
            return .disableDV(reason: "bit_depth_below_10(meta=\(metadataLabel),hvcc=\(hvccLabel))")
        }

        // Check for DV profile — this is the strongest signal
        guard let dvProfile = plan.dvProfile else {
            return .disableDV(reason: "missing_dv_profile")
        }
        guard dvProfile == 5 || dvProfile == 7 || dvProfile == 8 else {
            return .disableDV(reason: "unsupported_dv_profile_\(dvProfile)")
        }

        // Profile 8 is enabled only in strict runtime mode.
        // Default remains clean HDR10 fallback for broader stability.
        if dvProfile == 8, runtimeDVPackagingOverride != true {
            return .disableDV(reason: "profile8_nativebridge_hdr10_fallback")
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

    // MARK: - New Packaging Decision API

    /// Evaluates a complete packaging decision for the given mode.
    /// This is the primary API for the redesigned pipeline.
    public static func evaluatePackaging(
        plan: NativeBridgePlan,
        streamInfo: StreamInfo,
        device: DeviceCapabilityFingerprint,
        requestedMode: DolbyVisionPackagingMode
    ) -> NativeBridgePackagingDecision {
        let videoTrack = selectedVideoTrack(plan: plan, streamInfo: streamInfo)
        let isHEVC = HEVCCodecFamily.contains(videoTrack)

        // Derive the effective transfer characteristic for HLS VIDEO-RANGE signaling.
        // Priority: (1) explicit MKV Colour element, (2) plan-level DV/HDR metadata.
        // Main 10 is a bit-depth/profile property, not HDR evidence. Only explicit
        // transfer, Dolby Vision, or plan-level HDR range metadata may advertise HDR.
        let planRangeType = (plan.videoRangeType ?? "").lowercased()

        let effectiveTransfer: Int = {
            if let tc = videoTrack.transferCharacteristic, tc > 0 { return tc }
            // Any DV profile and HDR10/DOVI range types → PQ (ST.2084 = 16).
            if (plan.dvProfile ?? 0) > 0
                || planRangeType.contains("dovi")
                || planRangeType.contains("hdr10") { return 16 }
            return 1 // BT.709 (SDR fallback)
        }()
        let videoRange: String? = {
            switch effectiveTransfer {
            case 16: return "PQ"   // ST.2084 / Perceptual Quantizer
            case 18: return "HLG"  // Hybrid Log-Gamma
            default: return nil    // SDR — omit VIDEO-RANGE attribute
            }
        }()

        // Audio codec string for HLS CODECS attribute
        let audioTrack = plan.audioTrack ?? streamInfo.primaryAudioTrack
        let audioCodecString: String? = {
            guard let at = audioTrack else { return nil }
            let cn = at.codecName.lowercased()
            if cn.contains("eac3") || cn.contains("ec3") { return "ec-3" }
            if cn.contains("ac3") { return "ac-3" }
            return "mp4a.40.2"
        }()

        let dvProfile = plan.dvProfile
        let dvLevel = plan.dvLevel ?? 6
        let dvCompatId = plan.dvBlSignalCompatibilityId ?? 1
        let hevcSampleEntry = HEVCCodecFamily.effectiveSampleEntry(
            for: videoTrack,
            requestedMode: requestedMode,
            hasDolbyVision: [5, 7, 8].contains(dvProfile ?? -1)
        )
        let effectiveOutputSampleEntry: String = {
            if requestedMode == .primaryDolbyVisionExperimental,
               isHEVC,
               (dvProfile ?? 0) > 0 {
                return "dvh1"
            }
            return hevcSampleEntry
        }()
        let baseHEVCCodecString: String?
        if isHEVC {
            baseHEVCCodecString = videoTrack.codecPrivate.flatMap { codecPrivate in
                guard HEVCCodecParameter.hasValidStructure(
                    codecPrivate,
                    sampleEntry: effectiveOutputSampleEntry
                ) else { return nil }
                return HEVCCodecParameter(
                    configurationRecord: codecPrivate,
                    sampleEntry: hevcSampleEntry
                )?.value
            }
            guard baseHEVCCodecString != nil else {
                return makeUnsupportedHEVCDecision(
                    sampleEntry: effectiveOutputSampleEntry,
                    requestedMode: requestedMode
                )
            }
        } else {
            baseHEVCCodecString = nil
        }
        let baseCodecString = baseHEVCCodecString ?? "avc1.640028"
        let frameRate: Double? = 23.976

        switch requestedMode {
        case .dvProfile81Compatible:
            guard isHEVC, let dvProfile, (dvProfile == 5 || dvProfile == 7 || dvProfile == 8) else {
                return makeHDR10OnlyDecision(
                    baseCodec: baseCodecString,
                    audioCodec: audioCodecString,
                    videoRange: videoRange,
                    frameRate: frameRate,
                    reason: "dvProfile81Compatible requested but source is not DV HEVC (profile=\(dvProfile ?? -1))"
                )
            }

            let videoCodecs = [baseHEVCCodecString, audioCodecString].compactMap { $0 }.joined(separator: ",")
            let supplemental = String(format: "dvh1.%02d.%02d/db1p", dvProfile, dvLevel)

            return NativeBridgePackagingDecision(
                mode: .dvProfile81Compatible,
                videoEntry: VideoSampleEntryStrategy(
                    sampleEntryType: hevcSampleEntry,
                    includeHvcC: true,
                    includeDvcC: true,
                    dvProfile: dvProfile,
                    dvLevel: dvLevel,
                    dvCompatibilityId: dvCompatId,
                    ftypIncludesDby1: true,
                    stripDolbyVisionRPUNALs: false
                ),
                hlsSignaling: HLSMasterSignaling(
                    codecs: videoCodecs,
                    supplementalCodecs: supplemental,
                    videoRange: videoRange,
                    frameRate: frameRate
                ),
                expectation: PlaybackCapabilityExpectation(
                    floor: .hdr10,
                    ceiling: .dolbyVision,
                    explanation: "P\(dvProfile) backward-compatible: HDR10 floor, DV best-effort ceiling"
                ),
                reason: "DV Profile \(dvProfile) backward-compatible mode (hvc1 + dvcC + SUPPLEMENTAL-CODECS)"
            )

        case .hdr10OnlyFallback:
            return makeHDR10OnlyDecision(
                baseCodec: baseCodecString,
                audioCodec: audioCodecString,
                videoRange: videoRange,
                frameRate: frameRate,
                reason: "hdr10OnlyFallback explicitly selected"
            )

        case .primaryDolbyVisionExperimental:
            guard isHEVC, let dvProfile, dvProfile > 0 else {
                return makeHDR10OnlyDecision(
                    baseCodec: baseCodecString,
                    audioCodec: audioCodecString,
                    videoRange: videoRange,
                    frameRate: frameRate,
                    reason: "primaryDV requested but source has no DV profile"
                )
            }

            let dvCodecString = String(format: "dvh1.%02d.%02d", dvProfile, dvLevel)
            let videoCodecs = [dvCodecString, audioCodecString].compactMap { $0 }.joined(separator: ",")

            return NativeBridgePackagingDecision(
                mode: .primaryDolbyVisionExperimental,
                videoEntry: VideoSampleEntryStrategy(
                    sampleEntryType: "dvh1",
                    includeHvcC: true,
                    includeDvcC: true,
                    dvProfile: dvProfile,
                    dvLevel: dvLevel,
                    dvCompatibilityId: dvCompatId,
                    ftypIncludesDby1: true,
                    stripDolbyVisionRPUNALs: false
                ),
                hlsSignaling: HLSMasterSignaling(
                    codecs: videoCodecs,
                    supplementalCodecs: nil,
                    videoRange: videoRange,
                    frameRate: frameRate
                ),
                expectation: PlaybackCapabilityExpectation(
                    floor: .dolbyVision,
                    ceiling: .dolbyVision,
                    explanation: "Primary DV (experimental): DV-only, may fail on non-DV devices"
                ),
                reason: "DV Profile \(dvProfile) primary mode (experimental, dvh1 sample entry)"
            )
        }
    }

    private static func makeHDR10OnlyDecision(
        baseCodec: String,
        audioCodec: String?,
        videoRange: String?,
        frameRate: Double?,
        reason: String
    ) -> NativeBridgePackagingDecision {
        let videoCodecs = [baseCodec, audioCodec].compactMap { $0 }.joined(separator: ",")
        let isAVC = baseCodec.hasPrefix("avc")
        let sampleEntry = String(baseCodec.prefix(4))
        let isHDR = !isAVC && videoRange != nil
        return NativeBridgePackagingDecision(
            mode: .hdr10OnlyFallback,
            videoEntry: VideoSampleEntryStrategy(
                sampleEntryType: sampleEntry,
                includeHvcC: !isAVC,
                includeDvcC: false,
                ftypIncludesDby1: false,
                stripDolbyVisionRPUNALs: !isAVC
            ),
            hlsSignaling: HLSMasterSignaling(
                codecs: videoCodecs,
                supplementalCodecs: nil,
                videoRange: isAVC ? nil : videoRange,
                frameRate: frameRate
            ),
            expectation: PlaybackCapabilityExpectation(
                floor: isHDR ? .hdr10 : .sdr,
                ceiling: isHDR ? .hdr10 : .sdr,
                explanation: isHDR
                    ? "HEVC HDR — explicit transfer/range signaling, no DV signaling"
                    : "SDR — no HDR/DV signaling"
            ),
            reason: reason
        )
    }

    private static func makeUnsupportedHEVCDecision(
        sampleEntry: String,
        requestedMode: DolbyVisionPackagingMode
    ) -> NativeBridgePackagingDecision {
        NativeBridgePackagingDecision(
            mode: requestedMode,
            videoEntry: VideoSampleEntryStrategy(
                sampleEntryType: sampleEntry,
                includeHvcC: false,
                includeDvcC: false,
                ftypIncludesDby1: false,
                stripDolbyVisionRPUNALs: false
            ),
            hlsSignaling: HLSMasterSignaling(codecs: ""),
            expectation: PlaybackCapabilityExpectation(
                floor: .sdr,
                ceiling: .sdr,
                explanation: "Unsupported HEVC decoder configuration"
            ),
            reason: "unsupported_hevc_configuration"
        )
    }

    static func setExperimentalDVPackagingEnabledForTesting(_ enabled: Bool?) {
        experimentalDVPackagingOverride = enabled
    }

    static func setRuntimeDVPackagingEnabled(_ enabled: Bool?) {
        runtimeDVPackagingOverride = enabled
    }

    private static func isExperimentalDVPackagingEnabled() -> Bool {
        if let override = experimentalDVPackagingOverride {
            return override
        }

        if let runtime = runtimeDVPackagingOverride {
            return runtime
        }

        if let env = ProcessInfo.processInfo.environment["REELFIN_NATIVEBRIDGE_DV_EXPERIMENTAL"] {
            let normalized = env.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "1" || normalized == "true" || normalized == "yes" {
                return true
            }
            if normalized == "0" || normalized == "false" || normalized == "no" {
                return false
            }
        }

        return false
    }

    private static func selectedVideoTrack(
        plan: NativeBridgePlan,
        streamInfo: StreamInfo
    ) -> TrackInfo {
        streamInfo.tracks.first {
            $0.trackType == .video && $0.id == plan.videoTrack.id
        } ?? plan.videoTrack
    }

    private static func inferHEVCBitDepth(from codecPrivate: Data?) -> Int? {
        guard let codecPrivate, codecPrivate.count >= 20 else {
            return nil
        }
        // HEVCDecoderConfigurationRecord (hvcC):
        // byte 18: bitDepthLumaMinus8 (low 3 bits)
        // byte 19: bitDepthChromaMinus8 (low 3 bits)
        guard codecPrivate[0] == 0x01 else {
            return nil
        }

        let lumaMinus8 = Int(codecPrivate[18] & 0x07)
        let chromaMinus8 = Int(codecPrivate[19] & 0x07)
        let inferred = max(lumaMinus8, chromaMinus8) + 8
        guard (8...16).contains(inferred) else {
            return nil
        }
        return inferred
    }
}

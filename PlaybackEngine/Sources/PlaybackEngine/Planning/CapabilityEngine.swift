import Foundation

public protocol CapabilityEngineProtocol: Sendable {
    func computePlan(input: PlaybackPlanningInput) -> PlaybackPlan
}

public struct CapabilityEngine: CapabilityEngineProtocol, Sendable {
    public init() {}

    public func computePlan(input: PlaybackPlanningInput) -> PlaybackPlan {
        var traces: [PlanDecisionTrace] = []
        traces.append(
            PlanDecisionTrace(
                stage: .probe,
                outcome: .info,
                code: "probe.count",
                message: "Received \(input.probes.count) candidate media sources"
            )
        )

        let ranked = input.probes.sorted { lhs, rhs in
            qualityScore(for: lhs) > qualityScore(for: rhs)
        }

        for probe in ranked {
            let hdrMode = selectHDRMode(for: probe, constraints: input.constraints, device: input.device)
            let subtitleMode = selectSubtitleMode(for: probe)
            let seekMode: PlannedSeekMode = probe.hasKeyframeIndex ? .cueDriven : .serverManaged

            if isDirectPlayable(probe: probe, device: input.device) {
                traces.append(
                    PlanDecisionTrace(
                        stage: .laneSelection,
                        outcome: .accepted,
                        code: "lane.a",
                        message: "Selected Native Direct Play for source \(probe.sourceID)"
                    )
                )
                return PlaybackPlan(
                    itemID: input.itemID,
                    sourceID: probe.sourceID,
                    lane: .nativeDirectPlay,
                    targetURL: probe.directPlayURL,
                    selectedVideoCodec: probe.videoCodec,
                    selectedAudioCodec: chooseAudioCodec(for: probe),
                    selectedSubtitleCodec: chooseSubtitleCodec(for: probe),
                    hdrMode: hdrMode,
                    subtitleMode: subtitleMode == .burnIn ? .none : subtitleMode,
                    seekMode: seekMode,
                    fallbackGraph: [.selectAlternateAudio, .audioTranscodeOnly, .subtitleBurnIn, .fullTranscode, .reject],
                    reasonChain: PlaybackReasonChain(traces: traces)
                )
            }

            if isJITCompatible(probe: probe, device: input.device) {
                let needsAudioTranscode = audioNeedsTranscode(codec: probe.audioCodec)
                if needsAudioTranscode {
                    traces.append(
                        PlanDecisionTrace(
                            stage: .audioSelection,
                            outcome: .downgraded,
                            code: "audio.transcode.required",
                            message: "Source \(probe.sourceID) requires audio transcode fallback (codec=\(probe.audioCodec))"
                        )
                    )
                    if input.allowTranscoding, let url = probe.transcodeURL {
                        return PlaybackPlan(
                            itemID: input.itemID,
                            sourceID: probe.sourceID,
                            lane: .surgicalFallback,
                            targetURL: url,
                            selectedVideoCodec: probe.videoCodec,
                            selectedAudioCodec: "aac",
                            selectedSubtitleCodec: chooseSubtitleCodec(for: probe),
                            hdrMode: hdrMode,
                            subtitleMode: subtitleMode,
                            seekMode: .serverManaged,
                            fallbackGraph: [.audioTranscodeOnly, .subtitleBurnIn, .fullTranscode, .reject],
                            reasonChain: PlaybackReasonChain(traces: traces)
                        )
                    }
                }

                traces.append(
                    PlanDecisionTrace(
                        stage: .laneSelection,
                        outcome: .accepted,
                        code: "lane.b",
                        message: "Selected JIT Repackage HLS for source \(probe.sourceID)"
                    )
                )
                return PlaybackPlan(
                    itemID: input.itemID,
                    sourceID: probe.sourceID,
                    lane: .jitRepackageHLS,
                    targetURL: probe.directStreamURL ?? probe.directPlayURL,
                    selectedVideoCodec: probe.videoCodec,
                    selectedAudioCodec: chooseAudioCodec(for: probe),
                    selectedSubtitleCodec: chooseSubtitleCodec(for: probe),
                    hdrMode: hdrMode,
                    subtitleMode: subtitleMode,
                    seekMode: seekMode,
                    fallbackGraph: [.selectAlternateAudio, .audioTranscodeOnly, .subtitleBurnIn, .fullTranscode, .reject],
                    reasonChain: PlaybackReasonChain(traces: traces)
                )
            }

            if input.allowTranscoding, let transcodeURL = probe.transcodeURL {
                traces.append(
                    PlanDecisionTrace(
                        stage: .laneSelection,
                        outcome: .accepted,
                        code: "lane.c",
                        message: "Selected surgical fallback transcode for source \(probe.sourceID)"
                    )
                )
                return PlaybackPlan(
                    itemID: input.itemID,
                    sourceID: probe.sourceID,
                    lane: .surgicalFallback,
                    targetURL: transcodeURL,
                    selectedVideoCodec: probe.videoCodec,
                    selectedAudioCodec: "aac",
                    selectedSubtitleCodec: chooseSubtitleCodec(for: probe),
                    hdrMode: hdrMode,
                    subtitleMode: subtitleMode,
                    seekMode: .serverManaged,
                    fallbackGraph: [.audioTranscodeOnly, .subtitleBurnIn, .fullTranscode, .reject],
                    reasonChain: PlaybackReasonChain(traces: traces)
                )
            }

            traces.append(
                PlanDecisionTrace(
                    stage: .laneSelection,
                    outcome: .rejected,
                    code: "source.rejected",
                    message: "Rejected source \(probe.sourceID): incompatible with direct, JIT and fallback constraints"
                )
            )
        }

        return PlaybackPlan.rejection(itemID: input.itemID, sourceID: ranked.first?.sourceID, traces: traces, code: "no.viable.path")
    }

    private func isDirectPlayable(probe: MediaProbeResult, device: DeviceCapabilityFingerprint) -> Bool {
        guard let directURL = probe.directPlayURL else { return false }
        let containers = normalizedContainers(probe, fallbackURL: directURL)
        let containerOK = containers.contains { ["mp4", "m4v", "mov", "hls", "m3u8"].contains($0) }
        guard containerOK else { return false }

        let hasSupportedAudioTrack = probe.audioTracks.contains { isAudioSupported(codec: $0.codec, device: device) }
        let audioOK = isAudioSupported(codec: probe.audioCodec, device: device) || hasSupportedAudioTrack

        return isVideoSupported(codec: probe.videoCodec, device: device)
            && audioOK
    }

    private func isJITCompatible(probe: MediaProbeResult, device: DeviceCapabilityFingerprint) -> Bool {
        let containers = normalizedContainers(probe, fallbackURL: probe.directStreamURL ?? probe.directPlayURL)
        guard containers.contains("mkv") || containers.contains("matroska") || containers.contains("webm") else {
            return false
        }
        return isVideoSupported(codec: probe.videoCodec, device: device)
    }

    private func normalizedContainers(_ probe: MediaProbeResult, fallbackURL: URL?) -> [String] {
        if !probe.container.isEmpty {
            let tokens = probe.container
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if !tokens.isEmpty {
                return tokens
            }
        }
        if let fallbackURL, fallbackURL.pathExtension.lowercased() == "m3u8" {
            return ["hls"]
        }
        if let ext = fallbackURL?.pathExtension.lowercased(), !ext.isEmpty {
            return [ext]
        }
        return []
    }

    private func isVideoSupported(codec: String, device: DeviceCapabilityFingerprint) -> Bool {
        let c = codec.lowercased()
        if c.contains("hevc") || c.contains("h265") || c.contains("dvhe") || c.contains("dvh1") {
            return device.supportsHEVC
        }
        if c.contains("h264") || c.contains("avc1") {
            return device.supportsH264
        }
        if c.contains("av1") || c.contains("av01") {
            return device.supportsAV1
        }
        return false
    }

    private func isAudioSupported(codec: String, device: DeviceCapabilityFingerprint) -> Bool {
        let c = codec.lowercased()
        if c.contains("truehd") || c.contains("dts") {
            return false
        }
        if c.contains("eac3") || c.contains("ec3") {
            return device.supportsEAC3
        }
        if c.contains("ac3") {
            return device.supportsAC3
        }
        if c.contains("aac") {
            return device.supportsAAC
        }
        if c.contains("alac") {
            return device.supportsALAC
        }
        if c.contains("flac") {
            return device.supportsFLAC
        }
        if c.contains("opus") {
            return device.supportsOpus
        }
        return false
    }

    private func audioNeedsTranscode(codec: String) -> Bool {
        let support = AudioCodecSupport.classify(codec)
        return support == .needsConvert || support == .unknown
    }

    private func chooseAudioCodec(for probe: MediaProbeResult) -> String {
        let candidates = [probe.audioCodec] + probe.audioTracks.map(\.codec)
        if let aac = candidates.first(where: { $0.lowercased().contains("aac") }) {
            return aac.lowercased()
        }
        if let eac3 = candidates.first(where: { $0.lowercased().contains("eac3") || $0.lowercased().contains("ec3") }) {
            return eac3.lowercased()
        }
        if let ac3 = candidates.first(where: {
            let v = $0.lowercased()
            return v.contains("ac3") && !v.contains("eac3") && !v.contains("ec3")
        }) {
            return ac3.lowercased()
        }
        return probe.audioCodec
    }

    private func chooseSubtitleCodec(for probe: MediaProbeResult) -> String? {
        probe.subtitleTracks.first(where: { $0.isDefault })?.codec ?? probe.subtitleTracks.first?.codec
    }

    private func selectSubtitleMode(for probe: MediaProbeResult) -> PlannedSubtitleMode {
        let resolver = SubtitleStrategyResolver()
        let strategy = resolver.resolve(
            tracks: probe.subtitleTracks,
            selectedTrackID: nil,
            preferCustomOverlay: false,
            allowBurnIn: true
        )

        switch strategy.mode {
        case .disabled:
            return .none
        case .webVTT:
            return .webVTT
        case .burnIn:
            return .burnIn
        case .customOverlay:
            return .customOverlay
        }
    }

    private func selectHDRMode(for probe: MediaProbeResult, constraints: OutputConstraints, device: DeviceCapabilityFingerprint) -> PlannedHDRMode {
        let range = (probe.videoRangeType ?? "").lowercased()

        if constraints.airPlayActive || constraints.externalDisplayActive {
            if range.contains("dovi") || range.contains("dolby") {
                return .hdr10
            }
        }

        if (probe.dvProfile ?? 0) > 0, device.supportsDolbyVision {
            return .dolbyVision
        }
        if range.contains("hlg") {
            return .hlg
        }
        if range.contains("hdr") || range.contains("pq") || probe.hdr10PlusPresent {
            return .hdr10
        }
        if (probe.videoBitDepth ?? 8) >= 10 {
            return .passthrough
        }
        return .sdr
    }

    private func qualityScore(for probe: MediaProbeResult) -> Int {
        var score = 0
        let container = probe.container.lowercased()
        if container == "mkv" { score += 50 }

        let video = probe.videoCodec.lowercased()
        if video.contains("dvh1") || video.contains("dvhe") {
            score += 100
        } else if video.contains("hevc") || video.contains("h265") {
            score += 80
        } else if video.contains("h264") {
            score += 40
        }

        let audio = probe.audioCodec.lowercased()
        if audio.contains("eac3") { score += 50 }
        else if audio.contains("ac3") { score += 30 }
        else if audio.contains("aac") { score += 20 }

        if (probe.videoBitDepth ?? 8) >= 10 { score += 20 }
        if (probe.dvProfile ?? 0) > 0 { score += 40 }
        return score
    }
}

public struct FallbackPlanner: Sendable {
    public init() {}

    public func nextStep(after failure: FallbackAction) -> FallbackAction {
        switch failure {
        case .selectAlternateAudio:
            return .audioTranscodeOnly
        case .audioTranscodeOnly:
            return .subtitleBurnIn
        case .subtitleBurnIn:
            return .fullTranscode
        case .fullTranscode, .reject:
            return .reject
        }
    }
}

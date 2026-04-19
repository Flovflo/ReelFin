import Foundation
import Shared

/// A functional implementation of a fragmented MP4 (fMP4) repackager.
/// Generates an init segment (ftyp+moov) and media fragments (moof+mdat)
/// packed from ISO BMFF boxes using `MP4BoxWriter`.
public actor FMP4Repackager: Repackager {
    private let plan: NativeBridgePlan
    private let diagnostics: NativeBridgeDiagnosticsCollector?
    private var sequenceNumber: UInt32 = 1

    /// Packaging decision set by the session before init segment generation.
    /// Drives sample entry type, DV boxes, RPU stripping, and ftyp brands.
    private var packagingDecision: NativeBridgePackagingDecision?

    /// Legacy DV gate decision (kept for backward compat during transition).
    private var dvDecision: DolbyVisionGateDecision = .disableDV(reason: "not_evaluated")

    // MKV to MP4 timescale mapping
    // MKV uses nanoseconds traditionally, MP4 commonly uses 90000 for standard video playback
    private let timescale: UInt32 = 90000

    /// NALU length prefix size from the source hvcC/avcC record (1, 2, 3, or 4 bytes).
    /// Determined during init segment generation from codecPrivate byte 21 bits 0-1.
    private var sourceNALULengthSize: Int = 4
    private var strippedDVRPUSampleCount: Int = 0
    private var strippedDVRPUNALCount: Int = 0

    public init(plan: NativeBridgePlan, diagnostics: NativeBridgeDiagnosticsCollector? = nil) {
        self.plan = plan
        self.diagnostics = diagnostics
    }

    public func setPackagingDecision(_ decision: NativeBridgePackagingDecision) {
        self.packagingDecision = decision
        AppLog.nativeBridge.notice(
            "FMP4Repackager: packagingDecision set — mode=\(decision.mode.rawValue, privacy: .public) entry=\(decision.videoEntry.sampleEntryType, privacy: .public) dvcC=\(decision.videoEntry.includeDvcC, privacy: .public) stripRPU=\(decision.videoEntry.stripDolbyVisionRPUNALs, privacy: .public)"
        )
    }

    public func generateInitSegment(streamInfo: StreamInfo) async throws -> Data {
        AppLog.playback.debug("FMP4Repackager: Generating Init Segment for plan \(self.plan.whyChosen, privacy: .public)")

        // Extract source NALU length size from video track's hvcC/avcC codecPrivate
        if let videoTrack = streamInfo.tracks.first(where: { $0.trackType == .video }),
           let codecPrivate = videoTrack.codecPrivate, codecPrivate.count >= 22 {
            let isHEVC = videoTrack.codecName.lowercased().contains("hevc") ||
                         videoTrack.codecID.lowercased().contains("hevc")
            if isHEVC {
                sourceNALULengthSize = Int(codecPrivate[21] & 0x03) + 1
                let configVersion = codecPrivate[0]
                let generalProfile = codecPrivate[1]
                let numArrays = codecPrivate.count >= 23 ? codecPrivate[22] : 0
                let hexPrefix = codecPrivate.prefix(min(32, codecPrivate.count)).map { String(format: "%02x", $0) }.joined(separator: " ")
                AppLog.nativeBridge.notice(
                    "FMP4Repackager: hvcC version=\(configVersion) profile=\(generalProfile) naluLenSize=\(self.sourceNALULengthSize) numArrays=\(numArrays) first32=[\(hexPrefix, privacy: .public)]"
                )
            } else {
                if codecPrivate.count >= 5 {
                    sourceNALULengthSize = Int(codecPrivate[4] & 0x03) + 1
                }
                AppLog.nativeBridge.notice(
                    "FMP4Repackager: avcC NALULengthSize = \(self.sourceNALULengthSize) bytes, codecPrivate size=\(codecPrivate.count)"
                )
            }
        } else {
            AppLog.nativeBridge.warning("FMP4Repackager: No codecPrivate found for video track — NALU parsing may fail")
        }

        // --- New packaging-decision-driven path ---
        if let decision = packagingDecision {
            return try await generateInitSegmentFromDecision(streamInfo: streamInfo, decision: decision)
        }

        // --- Legacy path (backward compat for tests using DolbyVisionGate directly) ---
        dvDecision = DolbyVisionGate.evaluate(
            plan: plan,
            streamInfo: streamInfo,
            device: DeviceCapabilityFingerprint.current()
        )
        let hasDV = dvDecision.isEnabled
        if case .disableDV(let reason) = dvDecision {
            AppLog.nativeBridge.notice("DV disabled for init segment: \(reason, privacy: .public)")
        }

        var data = Data()
        data.append(MP4BoxWriter.writeFtyp(hasDolbyVision: hasDV))

        let dvConfig: MP4BoxWriter.DVConfig?
        if case .enableDV(let profile, let level, let compatId) = dvDecision {
            dvConfig = MP4BoxWriter.DVConfig(profile: profile, level: level, compatibilityId: compatId)
        } else {
            dvConfig = nil
        }

        let mp4Duration = UInt64((Double(streamInfo.durationNanoseconds) / 1_000_000_000.0) * Double(timescale))
        let tracksForMoov = normalizedTracksForMoov(streamInfo.tracks, hasDV: hasDV)
        data.append(MP4BoxWriter.writeMoov(tracks: tracksForMoov, duration: mp4Duration, timescale: timescale, dvConfig: dvConfig))
        Self.logInitSegment(data, hasDV: hasDV, dvConfig: dvConfig)
        await diagnostics?.recordInitSegment(data)
        return data
    }

    /// New decision-driven init segment generation (the primary path).
    private func generateInitSegmentFromDecision(streamInfo: StreamInfo, decision: NativeBridgePackagingDecision) async throws -> Data {
        let entry = decision.videoEntry

        var data = Data()
        data.append(MP4BoxWriter.writeFtyp(hasDolbyVision: entry.ftypIncludesDby1))

        let dvConfig: MP4BoxWriter.DVConfig?
        if entry.includeDvcC, let p = entry.dvProfile, let l = entry.dvLevel {
            dvConfig = MP4BoxWriter.DVConfig(profile: p, level: l, compatibilityId: entry.dvCompatibilityId ?? 1)
        } else {
            dvConfig = nil
        }

        let mp4Duration = UInt64((Double(streamInfo.durationNanoseconds) / 1_000_000_000.0) * Double(timescale))
        let tracksForMoov = normalizedTracksForDecision(streamInfo.tracks, decision: decision)
        data.append(MP4BoxWriter.writeMoov(
            tracks: tracksForMoov,
            duration: mp4Duration,
            timescale: timescale,
            sampleEntryType: entry.sampleEntryType,
            dvConfig: dvConfig
        ))

        AppLog.nativeBridge.notice(
            "FMP4Repackager: Init segment generated — \(data.count) bytes, mode=\(decision.mode.rawValue, privacy: .public) entry=\(entry.sampleEntryType, privacy: .public) dvcC=\(dvConfig != nil, privacy: .public)"
        )

        Self.logBoxTree(data: data, label: "Init Segment")
        if let tree = try? BMFFInspector.inspect(data) {
            AppLog.nativeBridge.notice("[NB-DIAG] Init Segment tree\n\(BMFFInspector.formatTree(tree), privacy: .public)")
        }

        // Verify boxes match decision
        let inspection = InitSegmentInspector.inspect(data)
        if entry.includeDvcC, !inspection.hasDvcC {
            AppLog.nativeBridge.error("[NB-DIAG] init.dv.boxes.missing — expected dvcC but not found in output")
        }
        if !entry.includeDvcC, inspection.hasDvcC {
            AppLog.nativeBridge.error("[NB-DIAG] init.dv.boxes.unexpected — dvcC present but not requested")
        }

        await diagnostics?.recordInitSegment(data)
        return data
    }

    /// Track normalization driven by the new packaging decision.
    private func normalizedTracksForDecision(_ tracks: [TrackInfo], decision: NativeBridgePackagingDecision) -> [TrackInfo] {
        let allowedIDs = Set([plan.videoTrack.id, plan.audioTrack?.id].compactMap { $0 })
        let filtered = tracks.filter { track in
            guard allowedIDs.contains(track.id) else { return false }
            return track.trackType == .video || track.trackType == .audio
        }

        switch decision.mode {
        case .hdr10OnlyFallback:
            // Normalize video to pure HEVC (strip DV codec identifiers)
            return filtered.map { track in
                guard track.trackType == .video else { return track }
                let color = normalizedColorMetadata(for: track, decision: decision)
                return TrackInfo(
                    id: track.id, trackType: track.trackType,
                    codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc",
                    language: track.language, isDefault: track.isDefault, isForced: track.isForced,
                    width: track.width, height: track.height, bitDepth: track.bitDepth,
                    chromaSubsampling: track.chromaSubsampling, codecPrivate: track.codecPrivate,
                    colourPrimaries: color.primaries, transferCharacteristic: color.transfer,
                    matrixCoefficients: color.matrix, maxCLL: track.maxCLL, maxFALL: track.maxFALL,
                    masteringLuminanceMax: track.masteringLuminanceMax, masteringLuminanceMin: track.masteringLuminanceMin,
                    sampleRate: track.sampleRate, channels: track.channels, channelLayout: track.channelLayout,
                    audioSupport: track.audioSupport, subtitleHandling: track.subtitleHandling
                )
            }
        case .dvProfile81Compatible, .primaryDolbyVisionExperimental:
            // Keep original DV coding, but inject BT.2020/PQ colr defaults when MKV colour metadata is absent.
            return filtered.map { track in
                guard track.trackType == .video else { return track }
                let color = normalizedColorMetadata(for: track, decision: decision)
                return TrackInfo(
                    id: track.id, trackType: track.trackType,
                    codecID: track.codecID, codecName: track.codecName,
                    language: track.language, isDefault: track.isDefault, isForced: track.isForced,
                    width: track.width, height: track.height, bitDepth: track.bitDepth,
                    chromaSubsampling: track.chromaSubsampling, codecPrivate: track.codecPrivate,
                    colourPrimaries: color.primaries, transferCharacteristic: color.transfer,
                    matrixCoefficients: color.matrix, maxCLL: track.maxCLL, maxFALL: track.maxFALL,
                    masteringLuminanceMax: track.masteringLuminanceMax, masteringLuminanceMin: track.masteringLuminanceMin,
                    sampleRate: track.sampleRate, channels: track.channels, channelLayout: track.channelLayout,
                    audioSupport: track.audioSupport, subtitleHandling: track.subtitleHandling
                )
            }
        }
    }

    private static func logInitSegment(_ data: Data, hasDV: Bool, dvConfig: MP4BoxWriter.DVConfig?) {
        let inspection = InitSegmentInspector.inspect(data)
        if hasDV, !inspection.hasDvcC, !inspection.hasDvvC {
            AppLog.nativeBridge.error(
                "[NB-DIAG] init.dv.boxes.missing — expectedDV=true hvcC=\(inspection.hasHvcC, privacy: .public) dvcC=\(inspection.hasDvcC, privacy: .public) dvvC=\(inspection.hasDvvC, privacy: .public)"
            )
        }
        logBoxTree(data: data, label: "Init Segment")
        if let tree = try? BMFFInspector.inspect(data) {
            AppLog.nativeBridge.notice("[NB-DIAG] Init Segment tree\n\(BMFFInspector.formatTree(tree), privacy: .public)")
        }
        AppLog.nativeBridge.notice(
            "FMP4Repackager: Init segment generated — \(data.count) bytes, DV=\(hasDV), dvConfig=\(dvConfig != nil ? "profile=\(dvConfig!.profile) level=\(dvConfig!.level) compat=\(dvConfig!.compatibilityId)" : "none")"
        )
    }

    private func normalizedTracksForMoov(_ tracks: [TrackInfo], hasDV: Bool) -> [TrackInfo] {
        let allowedIDs = Set([plan.videoTrack.id, plan.audioTrack?.id].compactMap { $0 })
        let filtered = tracks.filter { track in
            guard allowedIDs.contains(track.id) else { return false }
            return track.trackType == .video || track.trackType == .audio
        }

        guard !hasDV else { return filtered }
        return filtered.map { track in
            guard track.trackType == .video else { return track }
            let color = normalizedColorMetadataForLegacyPath(track)
            return TrackInfo(
                id: track.id,
                trackType: track.trackType,
                codecID: "V_MPEGH/ISO/HEVC",
                codecName: "hevc",
                language: track.language,
                isDefault: track.isDefault,
                isForced: track.isForced,
                width: track.width,
                height: track.height,
                bitDepth: track.bitDepth,
                chromaSubsampling: track.chromaSubsampling,
                codecPrivate: track.codecPrivate,
                colourPrimaries: color.primaries,
                transferCharacteristic: color.transfer,
                matrixCoefficients: color.matrix,
                maxCLL: track.maxCLL,
                maxFALL: track.maxFALL,
                masteringLuminanceMax: track.masteringLuminanceMax,
                masteringLuminanceMin: track.masteringLuminanceMin,
                sampleRate: track.sampleRate,
                channels: track.channels,
                channelLayout: track.channelLayout,
                audioSupport: track.audioSupport,
                subtitleHandling: track.subtitleHandling
            )
        }
    }

    private func normalizedColorMetadata(
        for track: TrackInfo,
        decision: NativeBridgePackagingDecision
    ) -> (primaries: Int?, transfer: Int?, matrix: Int?) {
        let existingPrimaries = track.colourPrimaries
        let existingTransfer = track.transferCharacteristic
        let existingMatrix = track.matrixCoefficients
        guard existingPrimaries == nil || existingTransfer == nil || existingMatrix == nil else {
            return (existingPrimaries, existingTransfer, existingMatrix)
        }

        // If playlist signaling says PQ, align MP4 colr defaults to BT.2020/PQ.
        let expectsPQ = (decision.hlsSignaling.videoRange?.uppercased() == "PQ")
        if expectsPQ {
            return (
                existingPrimaries ?? 9,  // BT.2020
                existingTransfer ?? 16,  // SMPTE ST 2084 (PQ)
                existingMatrix ?? 9      // BT.2020 non-constant luminance
            )
        }

        return (existingPrimaries, existingTransfer, existingMatrix)
    }

    private func normalizedColorMetadataForLegacyPath(_ track: TrackInfo) -> (primaries: Int?, transfer: Int?, matrix: Int?) {
        let existingPrimaries = track.colourPrimaries
        let existingTransfer = track.transferCharacteristic
        let existingMatrix = track.matrixCoefficients
        guard existingPrimaries == nil || existingTransfer == nil || existingMatrix == nil else {
            return (existingPrimaries, existingTransfer, existingMatrix)
        }

        let planRange = (plan.videoRangeType ?? "").lowercased()
        let likelyHDR = planRange.contains("dovi")
            || planRange.contains("hdr")
            || (plan.dvProfile ?? 0) > 0
        if likelyHDR {
            return (
                existingPrimaries ?? 9,
                existingTransfer ?? 16,
                existingMatrix ?? 9
            )
        }
        return (existingPrimaries, existingTransfer, existingMatrix)
    }

    public func generateFragment(packets: [DemuxedPacket]) async throws -> Data {
        guard !packets.isEmpty else { return Data() }

        // Step 1: Pre-process video packets — normalize NALUs to 4-byte length prefixes
        let videoID = plan.videoTrack.id
        let allowedTrackIDs = Set([plan.videoTrack.id, plan.audioTrack?.id].compactMap { $0 })
        let processed: [DemuxedPacket] = packets.compactMap { pkt in
            guard allowedTrackIDs.contains(pkt.trackID) else { return nil }
            guard pkt.trackID == videoID else { return pkt }
            let normalized = normalizeNALUs(data: pkt.data)
            let converted = stripDolbyVisionRPUNALUsIfNeeded(normalized)
            return DemuxedPacket(trackID: pkt.trackID, timestamp: pkt.timestamp,
                                 duration: pkt.duration, isKeyframe: pkt.isKeyframe,
                                 data: converted)
        }

        // Step 2: Build ordered track groups — video first, then audio
        var videoPackets: [DemuxedPacket] = []
        var audioPackets: [DemuxedPacket] = []
        let audioID = plan.audioTrack?.id
        for pkt in processed {
            if pkt.trackID == videoID {
                videoPackets.append(pkt)
            } else if let audioID, pkt.trackID == audioID {
                audioPackets.append(pkt)
            }
        }
        var trackGroups: [(trackID: Int, packets: [DemuxedPacket])] = []
        if !videoPackets.isEmpty { trackGroups.append((videoID, videoPackets)) }
        if !audioPackets.isEmpty, let aID = plan.audioTrack?.id {
            trackGroups.append((aID, audioPackets))
        }

        // Step 3: Pre-calculate exact moof size so data_offset is correct
        // moof = 8 (header) + 16 (mfhd) + sum_per_track(8 + 16 + 20 + 20 + n*12)
        //      = 8 + 16 + numTracks*(64) + totalPackets*12
        let totalPackets = trackGroups.reduce(0) { $0 + $1.packets.count }
        let moofSize = 8 + 16 + trackGroups.count * 64 + totalPackets * 12

        // Step 4: Compute per-track data_offset (relative to start of moof)
        // First track starts right after moof + mdat header (8 bytes)
        var mdatDataOffset = moofSize + 8  // +8 for mdat box header
        var trackDataOffsets: [Int: Int] = [:]
        for group in trackGroups {
            trackDataOffsets[group.trackID] = mdatDataOffset
            mdatDataOffset += group.packets.reduce(0) { $0 + $1.data.count }
        }

        let startPts = processed.first?.timestamp ?? 0
        AppLog.playback.debug("FMP4Repackager: Fragment \(self.sequenceNumber) — \(processed.count) pkts, moofSize=\(moofSize). PTS=\(startPts)")

        // Debug: log NALU types for the first keyframe video packet
        if sequenceNumber <= 3, let firstKeyframe = videoPackets.first(where: { $0.isKeyframe }) {
            let naluTypes = Self.extractNALUTypes(from: firstKeyframe.data, lengthSize: 4)
            let desc = naluTypes.map { "type=\($0)" }.joined(separator: ", ")
            AppLog.nativeBridge.notice("FMP4Repackager: Keyframe NALUs (frag \(self.sequenceNumber)): [\(desc, privacy: .public)]")
        }
        if sequenceNumber <= 3, strippedDVRPUSampleCount > 0 || strippedDVRPUNALCount > 0 {
            AppLog.nativeBridge.notice(
                "FMP4Repackager: Stripped DV RPUs for HDR10 compatibility samples=\(self.strippedDVRPUSampleCount, privacy: .public) nalus=\(self.strippedDVRPUNALCount, privacy: .public)"
            )
        }

        // Step 5: Write moof then mdat
        let moof = writeMoofWithOffsets(trackGroups: trackGroups, trackDataOffsets: trackDataOffsets)
        let mdat = writeMdatForGroups(trackGroups: trackGroups)
        var fragment = Data()
        fragment.append(moof)
        fragment.append(mdat)

        let emittedSequence = Int(sequenceNumber)
        if emittedSequence <= 3, let tree = try? BMFFInspector.inspect(fragment) {
            AppLog.nativeBridge.notice("[NB-DIAG] Fragment #\(emittedSequence, privacy: .public) tree\n\(BMFFInspector.formatTree(tree), privacy: .public)")
        }
        await diagnostics?.recordFragment(
            sequenceNumber: emittedSequence,
            fragment: fragment,
            moofSize: moof.count,
            mdatSize: mdat.count,
            sampleCount: processed.count,
            firstPTS: startPts
        )

        sequenceNumber += 1
        return fragment
    }

    // MARK: - Box Builders

    private func writeMoofWithOffsets(
        trackGroups: [(trackID: Int, packets: [DemuxedPacket])],
        trackDataOffsets: [Int: Int]
    ) -> Data {
        var payload = writeMfhd()
        for group in trackGroups {
            let dataOffset = Int32(trackDataOffsets[group.trackID] ?? 0)
            payload.append(writeTraf(trackID: UInt32(group.trackID), packets: group.packets, dataOffset: dataOffset))
        }
        return MP4BoxWriter.writeBox(type: "moof", payload: payload)
    }

    /// Legacy single-entry moof for internal use (kept for API compatibility)
    private func writeMoof(packets: [DemuxedPacket]) -> Data {
        var payload = writeMfhd()
        let grouped = Dictionary(grouping: packets, by: { $0.trackID })
        for (trackID, trackPackets) in grouped.sorted(by: { $0.key < $1.key }) {
            payload.append(writeTraf(trackID: UInt32(trackID), packets: trackPackets, dataOffset: 0))
        }
        return MP4BoxWriter.writeBox(type: "moof", payload: payload)
    }
    
    private func writeMfhd() -> Data {
        let payload = MP4BoxWriter.writeUInt32(sequenceNumber)
        return MP4BoxWriter.writeFullBox(type: "mfhd", payload: payload)
    }
    
    private func writeTraf(trackID: UInt32, packets: [DemuxedPacket], dataOffset: Int32) -> Data {
        var payload = writeTfhd(trackID: trackID)
        if let firstPacket = packets.first {
            let baseDecodeTime = UInt64((Double(firstPacket.timestamp) / 1_000_000_000.0) * Double(timescale))
            payload.append(writeTfdt(baseDecodeTime: baseDecodeTime))
        }
        payload.append(writeTrun(packets: packets, dataOffset: dataOffset))
        return MP4BoxWriter.writeBox(type: "traf", payload: payload)
    }
    
    private func writeTfhd(trackID: UInt32) -> Data {
        let payload = MP4BoxWriter.writeUInt32(trackID)
        // flags: default-base-is-moof (0x020000)
        return MP4BoxWriter.writeFullBox(type: "tfhd", flags: 0x020000, payload: payload)
    }
    
    private func writeTfdt(baseDecodeTime: UInt64) -> Data {
        let payload = MP4BoxWriter.writeUInt64(baseDecodeTime)
        // version 1 for 64-bit baseDecodeTime
        return MP4BoxWriter.writeFullBox(type: "tfdt", version: 1, payload: payload)
    }
    
    /// data-offset-present (0x0001) | sample-duration-present (0x0100) |
    /// sample-size-present (0x0200) | sample-flags-present (0x0400)
    private func writeTrun(packets: [DemuxedPacket], dataOffset: Int32) -> Data {
        let flags: UInt32 = 0x0001 | 0x0100 | 0x0200 | 0x0400

        var payload = MP4BoxWriter.writeUInt32(UInt32(packets.count))

        // data_offset is a signed int32 — write as big-endian
        payload.append(MP4BoxWriter.writeUInt32(UInt32(bitPattern: dataOffset)))

        for packet in packets {
            let duration = UInt32((Double(packet.duration) / 1_000_000_000.0) * Double(timescale))
            payload.append(MP4BoxWriter.writeUInt32(duration))
            payload.append(MP4BoxWriter.writeUInt32(UInt32(packet.data.count)))
            // sample_flags: depends_on=2 (I-frame), non-sync=1 (P/B)
            let sampleFlags: UInt32 = packet.isKeyframe ? 0x02000000 : 0x01010000
            payload.append(MP4BoxWriter.writeUInt32(sampleFlags))
        }

        return MP4BoxWriter.writeFullBox(type: "trun", version: 0, flags: flags, payload: payload)
    }

    private func writeMdatForGroups(trackGroups: [(trackID: Int, packets: [DemuxedPacket])]) -> Data {
        // Samples already NALU-converted; just concatenate in track-group order
        var payload = Data()
        for group in trackGroups {
            for packet in group.packets {
                payload.append(packet.data)
            }
        }
        return MP4BoxWriter.writeBox(type: "mdat", payload: payload)
    }

    // MARK: - Debug Utilities

    /// Extracts HEVC NAL unit types from length-prefixed data for diagnostic logging.
    /// Returns array of NAL unit type values (e.g., 32=VPS, 33=SPS, 34=PPS, 19/20=IDR, 62/63=UNSPEC/RPU).
    private static func extractNALUTypes(from data: Data, lengthSize: Int) -> [Int] {
        var types: [Int] = []
        var offset = 0
        while offset + lengthSize < data.count {
            var naluLen: UInt32 = 0
            for i in 0..<lengthSize {
                naluLen = (naluLen << 8) | UInt32(data[offset + i])
            }
            offset += lengthSize
            guard naluLen > 0, offset < data.count else { break }
            // HEVC NAL unit type is in bits 1-6 of the first byte (byte >> 1) & 0x3F
            let naluType = Int((data[offset] >> 1) & 0x3F)
            types.append(naluType)
            offset += Int(naluLen)
        }
        return types
    }

    // MARK: - Diagnostic Logging

    /// [NB-DIAG] Logs the top-level box tree of an MP4 segment for debugging.
    private static func logBoxTree(data: Data, label: String) {
        var entries: [String] = []
        var offset = 0
        while offset + 8 <= data.count {
            let size = Int(data[offset]) << 24 | Int(data[offset+1]) << 16 | Int(data[offset+2]) << 8 | Int(data[offset+3])
            guard size >= 8, offset + size <= data.count else { break }
            let type = String(data: data[(offset+4)..<(offset+8)], encoding: .ascii) ?? "????"
            entries.append("\(type):\(size)")
            offset += size
        }
        AppLog.nativeBridge.notice("[NB-DIAG] \(label, privacy: .public) boxes: [\(entries.joined(separator: ", "), privacy: .public)]")
    }

    // MARK: - NALU Utilities

    /// Normalizes video frame NALUs to 4-byte length-prefixed format for fMP4.
    /// Handles both length-prefixed (from MKV hvcC) and Annex-B (rare, from some muxers) input.
    private func normalizeNALUs(data: Data) -> Data {
        guard data.count > 4 else { return data }

        // Detect format: Annex-B starts with 00 00 00 01 or 00 00 01
        let isAnnexB = (data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1) ||
                       (data[0] == 0 && data[1] == 0 && data[2] == 1)

        if isAnnexB {
            return convertAnnexBToLengthPrefixed(data: data)
        }

        // Data is length-prefixed from source; re-prefix to 4-byte if needed
        let srcLen = sourceNALULengthSize
        if srcLen == 4 {
            // Already 4-byte prefixed — pass through directly
            return data
        }

        // Re-prefix from srcLen-byte to 4-byte length prefixes
        return rePrefixNALUs(data: data, sourceLengthSize: srcLen)
    }

    /// Re-prefixes NALUs from `sourceLengthSize`-byte to 4-byte length prefixes.
    private func rePrefixNALUs(data: Data, sourceLengthSize: Int) -> Data {
        var result = Data()
        result.reserveCapacity(data.count + data.count / 8) // slight overallocation for prefix growth
        var offset = 0

        while offset + sourceLengthSize <= data.count {
            var naluLength: UInt32 = 0
            for i in 0..<sourceLengthSize {
                naluLength = (naluLength << 8) | UInt32(data[offset + i])
            }
            offset += sourceLengthSize

            guard naluLength > 0, offset + Int(naluLength) <= data.count else {
                AppLog.nativeBridge.warning(
                    "NALU re-prefix: invalid length \(naluLength) at offset \(offset), remaining=\(data.count - offset)"
                )
                break
            }

            result.append(MP4BoxWriter.writeUInt32(naluLength))
            result.append(data[offset..<offset + Int(naluLength)])
            offset += Int(naluLength)
        }

        return result
    }

    /// Converts Annex-B style NAL units (00 00 00 01 / 00 00 01) to 4-byte length-prefixed style.
    private func convertAnnexBToLengthPrefixed(data: Data) -> Data {
        var result = Data()
        result.reserveCapacity(data.count)

        var i = 0
        while i < data.count {
            let startCodeLength: Int
            if i + 3 < data.count && data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 && data[i + 3] == 1 {
                startCodeLength = 4
            } else if i + 2 < data.count && data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 {
                startCodeLength = 3
            } else {
                i += 1
                continue
            }

            let payloadStart = i + startCodeLength
            var nextStart = data.count
            var scan = payloadStart
            while scan < data.count {
                if scan + 3 < data.count && data[scan] == 0 && data[scan + 1] == 0 && data[scan + 2] == 0 && data[scan + 3] == 1 {
                    nextStart = scan
                    break
                }
                if scan + 2 < data.count && data[scan] == 0 && data[scan + 1] == 0 && data[scan + 2] == 1 {
                    nextStart = scan
                    break
                }
                scan += 1
            }

            guard payloadStart <= nextStart else {
                i += 1
                continue
            }

            let naluLength = UInt32(nextStart - payloadStart)
            result.append(MP4BoxWriter.writeUInt32(naluLength))
            if payloadStart < nextStart {
                result.append(data[payloadStart..<nextStart])
            }

            i = nextStart
        }

        return result
    }

    private func stripDolbyVisionRPUNALUsIfNeeded(_ data: Data) -> Data {
        guard shouldStripDolbyVisionRPU() else { return data }
        // HEVC Dolby Vision RPUs in single-layer streams are typically carried in
        // UNSPEC62/UNSPEC63 NAL units. Strip them for clean HDR10 fallback output.
        var offset = 0
        var output = Data()
        var removed = 0
        var kept = 0
        output.reserveCapacity(data.count)

        while offset + 4 <= data.count {
            let naluLength = Int(data[offset]) << 24
                | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8
                | Int(data[offset + 3])
            offset += 4
            guard naluLength > 0, offset + naluLength <= data.count else {
                break
            }

            let naluStart = offset
            let naluEnd = offset + naluLength
            let naluType = Int((data[naluStart] >> 1) & 0x3F)
            if naluType == 62 || naluType == 63 {
                removed += 1
            } else {
                kept += 1
                output.append(MP4BoxWriter.writeUInt32(UInt32(naluLength)))
                output.append(data[naluStart..<naluEnd])
            }
            offset = naluEnd
        }

        guard removed > 0, kept > 0 else {
            return data
        }
        strippedDVRPUSampleCount += 1
        strippedDVRPUNALCount += removed
        return output
    }

    private func shouldStripDolbyVisionRPU() -> Bool {
        // New packaging-decision-driven path takes priority
        if let decision = packagingDecision {
            return decision.videoEntry.stripDolbyVisionRPUNALs
        }
        // Legacy path fallback
        if case .disableDV = dvDecision {
            return true
        }
        return false
    }
}

struct BMFFInspectNode: Sendable, Equatable {
    let type: String
    let size: Int
    let offset: Int
    let summary: String?
    let children: [BMFFInspectNode]
}

public struct InitSegmentInspection: Sendable, Equatable {
    public let hasHvcC: Bool
    public let hasDvcC: Bool
    public let hasDvvC: Bool
    public let videoSampleEntry: String?
    public let audioSampleEntry: String?
    public let inferredMode: EffectivePlaybackVideoMode

    public init(
        hasHvcC: Bool,
        hasDvcC: Bool,
        hasDvvC: Bool,
        videoSampleEntry: String? = nil,
        audioSampleEntry: String? = nil,
        inferredMode: EffectivePlaybackVideoMode
    ) {
        self.hasHvcC = hasHvcC
        self.hasDvcC = hasDvcC
        self.hasDvvC = hasDvvC
        self.videoSampleEntry = videoSampleEntry
        self.audioSampleEntry = audioSampleEntry
        self.inferredMode = inferredMode
    }
}

enum InitSegmentInspector {
    static func inspect(_ data: Data) -> InitSegmentInspection {
        guard let tree = try? BMFFInspector.inspect(data) else {
            return InitSegmentInspection(
                hasHvcC: false,
                hasDvcC: false,
                hasDvvC: false,
                videoSampleEntry: nil,
                audioSampleEntry: nil,
                inferredMode: .unknown
            )
        }
        let types = flattenTypes(tree)
        let hasHvcC = types.contains("hvcC")
        let hasDvcC = types.contains("dvcC")
        let hasDvvC = types.contains("dvvC")
        let videoSampleEntry = firstMatchingType(
            in: types,
            preferredOrder: ["dvh1", "dvhe", "hvc1", "hev1", "avc1", "avc3"]
        )
        let audioSampleEntry = firstMatchingType(
            in: types,
            preferredOrder: ["ec-3", "ac-3", "mp4a"]
        )

        let mode: EffectivePlaybackVideoMode
        if hasDvcC || hasDvvC {
            mode = .dolbyVision
        } else if hasHvcC {
            mode = .hdr10
        } else if types.contains("avcC") {
            mode = .sdr
        } else {
            mode = .unknown
        }

        return InitSegmentInspection(
            hasHvcC: hasHvcC,
            hasDvcC: hasDvcC,
            hasDvvC: hasDvvC,
            videoSampleEntry: videoSampleEntry,
            audioSampleEntry: audioSampleEntry,
            inferredMode: mode
        )
    }

    private static func flattenTypes(_ nodes: [BMFFInspectNode]) -> [String] {
        var values: [String] = []
        func walk(_ current: [BMFFInspectNode]) {
            for node in current {
                values.append(node.type)
                walk(node.children)
            }
        }
        walk(nodes)
        return values
    }

    private static func firstMatchingType(in types: [String], preferredOrder: [String]) -> String? {
        for candidate in preferredOrder where types.contains(candidate) {
            return candidate
        }
        return nil
    }
}

enum BMFFInspector {
    private static let containerTypes: Set<String> = [
        "moov", "trak", "mdia", "minf", "stbl", "mvex", "moof", "traf", "dinf"
    ]

    private static let videoSampleEntryTypes: Set<String> = [
        "avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe"
    ]

    private static let audioSampleEntryTypes: Set<String> = [
        "mp4a", "ac-3", "ec-3"
    ]

    static func inspect(_ data: Data) throws -> [BMFFInspectNode] {
        try parseBoxes(data, range: 0..<data.count)
    }

    static func formatTree(_ nodes: [BMFFInspectNode]) -> String {
        var lines: [String] = []

        func walk(_ node: BMFFInspectNode, depth: Int) {
            let indent = String(repeating: "  ", count: depth)
            if let summary = node.summary, !summary.isEmpty {
                lines.append("\(indent)\(node.type) size=\(node.size) off=\(node.offset) \(summary)")
            } else {
                lines.append("\(indent)\(node.type) size=\(node.size) off=\(node.offset)")
            }
            node.children.forEach { walk($0, depth: depth + 1) }
        }

        nodes.forEach { walk($0, depth: 0) }
        return lines.joined(separator: "\n")
    }

    private static func parseBoxes(_ data: Data, range: Range<Int>) throws -> [BMFFInspectNode] {
        var nodes: [BMFFInspectNode] = []
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            guard cursor + 8 <= range.upperBound else { break }
            var headerSize = 8
            var size = Int(readUInt32(data, at: cursor))
            let type = readType(data, at: cursor + 4)

            if size == 1 {
                guard cursor + 16 <= range.upperBound else { break }
                size = Int(readUInt64(data, at: cursor + 8))
                headerSize = 16
            } else if size == 0 {
                size = range.upperBound - cursor
            }

            guard size >= headerSize else { break }
            let end = cursor + size
            guard end <= range.upperBound else { break }

            let payloadRange = (cursor + headerSize)..<end
            var children: [BMFFInspectNode] = []
            var summary: String?

            if containerTypes.contains(type) {
                children = try parseBoxes(data, range: payloadRange)
            } else if type == "stsd" {
                let parsed = try parseStsdEntries(data, payloadRange: payloadRange)
                children = parsed.0
                summary = parsed.1
            } else if videoSampleEntryTypes.contains(type) || audioSampleEntryTypes.contains(type) {
                let parsed = try parseSampleEntryChildren(data, type: type, payloadRange: payloadRange)
                children = parsed.0
                summary = parsed.1
            } else {
                summary = summarizeBox(data, type: type, payloadRange: payloadRange)
            }

            nodes.append(BMFFInspectNode(type: type, size: size, offset: cursor, summary: summary, children: children))
            cursor = end
        }

        return nodes
    }

    private static func parseStsdEntries(_ data: Data, payloadRange: Range<Int>) throws -> ([BMFFInspectNode], String) {
        guard payloadRange.count >= 8 else { return ([], "invalid_stsd_payload") }
        let entryCount = Int(readUInt32(data, at: payloadRange.lowerBound + 4))
        var entries: [BMFFInspectNode] = []

        var cursor = payloadRange.lowerBound + 8
        for _ in 0..<entryCount where cursor + 8 <= payloadRange.upperBound {
            let size = Int(readUInt32(data, at: cursor))
            guard size >= 8, cursor + size <= payloadRange.upperBound else { break }
            let type = readType(data, at: cursor + 4)
            let payload = (cursor + 8)..<(cursor + size)
            let parsed = try parseSampleEntryChildren(data, type: type, payloadRange: payload)
            entries.append(BMFFInspectNode(type: type, size: size, offset: cursor, summary: parsed.1, children: parsed.0))
            cursor += size
        }

        return (entries, "entryCount=\(entryCount)")
    }

    private static func parseSampleEntryChildren(_ data: Data, type: String, payloadRange: Range<Int>) throws -> ([BMFFInspectNode], String) {
        let headerBytes: Int
        var summaryParts: [String] = []

        if videoSampleEntryTypes.contains(type) {
            headerBytes = 78
            if payloadRange.count >= 28 {
                let width = Int(readUInt16(data, at: payloadRange.lowerBound + 24))
                let height = Int(readUInt16(data, at: payloadRange.lowerBound + 26))
                summaryParts.append("width=\(width)")
                summaryParts.append("height=\(height)")
            }
        } else if audioSampleEntryTypes.contains(type) {
            headerBytes = 28
            if payloadRange.count >= 28 {
                // ISO/IEC 14496-12 AudioSampleEntry:
                // reserved(6) + data_ref_idx(2) + reserved(8) + channelcount(2) + samplesize(2)
                // + pre_defined(2) + reserved(2) + samplerate(4, 16.16 fixed-point)
                let channels = Int(readUInt16(data, at: payloadRange.lowerBound + 16))
                let sampleRate = Int(readUInt32(data, at: payloadRange.lowerBound + 24) >> 16)
                summaryParts.append("channels=\(channels)")
                summaryParts.append("sampleRate=\(sampleRate)")
            }
        } else {
            headerBytes = 0
        }

        let children: [BMFFInspectNode]
        let childStart = payloadRange.lowerBound + headerBytes
        if childStart < payloadRange.upperBound {
            children = try parseBoxes(data, range: childStart..<payloadRange.upperBound)
        } else {
            children = []
        }

        return (children, summaryParts.joined(separator: " "))
    }

    private static func summarizeBox(_ data: Data, type: String, payloadRange: Range<Int>) -> String? {
        switch type {
        case "hdlr":
            guard payloadRange.count >= 12 else { return nil }
            let handler = readType(data, at: payloadRange.lowerBound + 8)
            return "handler=\(handler)"
        case "mdhd":
            guard payloadRange.count >= 4 else { return nil }
            let version = Int(data[payloadRange.lowerBound])
            if version == 1, payloadRange.count >= 32 {
                let timescale = readUInt32(data, at: payloadRange.lowerBound + 20)
                let duration = readUInt64(data, at: payloadRange.lowerBound + 24)
                return "version=1 timescale=\(timescale) duration=\(duration)"
            } else if payloadRange.count >= 20 {
                let timescale = readUInt32(data, at: payloadRange.lowerBound + 12)
                let duration = readUInt32(data, at: payloadRange.lowerBound + 16)
                return "version=0 timescale=\(timescale) duration=\(duration)"
            }
            return nil
        case "hvcC":
            guard payloadRange.count >= 23 else { return "short_hvcC" }
            let version = data[payloadRange.lowerBound]
            let profile = data[payloadRange.lowerBound + 1]
            let nalLenSize = Int(data[payloadRange.lowerBound + 21] & 0x03) + 1
            let numArrays = Int(data[payloadRange.lowerBound + 22])
            return "version=\(version) profile=\(profile) naluLen=\(nalLenSize) arrays=\(numArrays)"
        case "dvcC":
            guard payloadRange.count >= 5 else { return "short_dvcC" }
            let packed = Int(data[payloadRange.lowerBound + 2]) << 16
                | Int(data[payloadRange.lowerBound + 3]) << 8
                | Int(data[payloadRange.lowerBound + 4])
            let profile = (packed >> 17) & 0x7F
            let level = (packed >> 11) & 0x3F
            let compat = (packed >> 4) & 0x0F
            return "profile=\(profile) level=\(level) compat=\(compat)"
        case "dec3":
            guard payloadRange.count >= 5 else { return "short_dec3" }
            let firstWord = readUInt16(data, at: payloadRange.lowerBound)
            let dataRate = Int((firstWord >> 3) & 0x1FFF)
            let numIndSub = Int(firstWord & 0x0007) + 1
            let b2 = data[payloadRange.lowerBound + 2]
            let b4 = data[payloadRange.lowerBound + 4]
            let fscod = Int((b2 & 0b1100_0000) >> 6)
            let sampleRate: Int = {
                switch fscod {
                case 0: return 48_000
                case 1: return 44_100
                case 2: return 32_000
                default: return 0
                }
            }()
            let numDepSub = Int((b4 & 0b0001_1110) >> 1)
            return "dataRate=\(dataRate) numIndSub=\(numIndSub) fscod=\(fscod) sampleRate=\(sampleRate) numDepSub=\(numDepSub)"
        case "trex":
            guard payloadRange.count >= 20 else { return nil }
            let trackID = readUInt32(data, at: payloadRange.lowerBound + 4)
            return "trackID=\(trackID)"
        case "tfhd":
            guard payloadRange.count >= 8 else { return nil }
            let flags = UInt32(data[payloadRange.lowerBound + 1]) << 16
                | UInt32(data[payloadRange.lowerBound + 2]) << 8
                | UInt32(data[payloadRange.lowerBound + 3])
            let trackID = readUInt32(data, at: payloadRange.lowerBound + 4)
            return "flags=0x\(String(flags, radix: 16)) trackID=\(trackID)"
        case "tfdt":
            guard payloadRange.count >= 8 else { return nil }
            let version = Int(data[payloadRange.lowerBound])
            if version == 1, payloadRange.count >= 12 {
                let decodeTime = readUInt64(data, at: payloadRange.lowerBound + 4)
                return "version=1 baseDecodeTime=\(decodeTime)"
            } else {
                let decodeTime = readUInt32(data, at: payloadRange.lowerBound + 4)
                return "version=0 baseDecodeTime=\(decodeTime)"
            }
        case "trun":
            guard payloadRange.count >= 12 else { return nil }
            let flags = UInt32(data[payloadRange.lowerBound + 1]) << 16
                | UInt32(data[payloadRange.lowerBound + 2]) << 8
                | UInt32(data[payloadRange.lowerBound + 3])
            let sampleCount = readUInt32(data, at: payloadRange.lowerBound + 4)
            let dataOffset = Int32(bitPattern: readUInt32(data, at: payloadRange.lowerBound + 8))
            return "flags=0x\(String(flags, radix: 16)) sampleCount=\(sampleCount) dataOffset=\(dataOffset)"
        default:
            return nil
        }
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(readUInt32(data, at: offset)) << 32
            | UInt64(readUInt32(data, at: offset + 4))
    }

    private static func readType(_ data: Data, at offset: Int) -> String {
        String(decoding: [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]], as: UTF8.self)
    }
}

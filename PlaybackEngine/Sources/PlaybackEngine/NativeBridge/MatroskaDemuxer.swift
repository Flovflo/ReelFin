import Foundation
import Shared

/// A functional implementation of a Matroska (MKV / WebM) demuxer in pure Swift.
/// It uses `EBMLParser` and `HTTPRangeReader` to stream and parse binary data on demand.
public actor MatroskaDemuxer: Demuxer {
    private let reader: HTTPRangeReader
    private let plan: NativeBridgePlan

    private var isOpened = false
    private var eofReached = false
    
    // MKV State
    private var fileOffset: Int64 = 0
    private var segmentDataStart: Int64 = 0
    private var segmentDataSize: Int64 = -1
    
    // Extracted Info
    private var timecodeScale: UInt64 = 1_000_000 // default 1ms
    private var durationFloat: Double = 0
    private var parsedTracks: [TrackInfo] = []
    
    // Cluster reading state
    private var currentClusterTimecode: UInt64 = 0
    private var clusterEndOffset: Int64 = -1
    
    // Extracted Cues
    private struct CuePoint: Equatable {
        let timecode: UInt64
        let clusterOffset: UInt64
    }
    private var extractedCues: [CuePoint] = []

    // Per-track default duration in nanoseconds (from TrackEntry\DefaultDuration)
    private var trackDefaultDurations: [Int: Int64] = [:]

    // Queue for laced frames (when a block contains multiple frames via lacing)
    private var pendingPackets: [DemuxedPacket] = []

    // Buffer for parsing.
    // fileOffset   = absolute file position of the current read head (same semantic as before).
    // bufferBase   = absolute file position of buffer[0].
    // bufferReadOffset (computed) = index in buffer of the read head = fileOffset - bufferBase.
    // Valid data: buffer[bufferReadOffset..<buffer.count].
    private var buffer = Data()
    private var bufferBase: Int64 = 0

    private var bufferReadOffset: Int { Int(fileOffset - bufferBase) }
    
    public init(reader: HTTPRangeReader, plan: NativeBridgePlan) {
        self.reader = reader
        self.plan = plan
    }

    public func open() async throws -> StreamInfo {
        guard !isOpened else {
            throw NativeBridgeError.demuxerFailed("Demuxer is already open.")
        }
        
        AppLog.nativeBridge.notice("[NB-DIAG] demux.open.enter — source=\(self.plan.sourceURL.lastPathComponent, privacy: .public)")
        
        // 1. Read EBML Header
        let networkStart = Date()
        try await ensureBuffer(size: 1024)
        let networkMs = Date().timeIntervalSince(networkStart) * 1000
        AppLog.nativeBridge.notice("[NB-DIAG] demux.network.first-bytes — \(self.buffer.count) bytes buffered in \(networkMs, format: .fixed(precision: 1))ms")
        
        let ro0 = bufferReadOffset
        var (id, length) = try EBMLParser.readElementID(data: buffer, offset: ro0)
        guard id == EBMLParser.idEBML else {
            AppLog.nativeBridge.error("[NB-DIAG] demux.ebml.failed — bad header ID=\(String(format:"%X", id), privacy: .public)")
            throw NativeBridgeError.invalidMKV("Invalid EBML Header ID: \(String(format:"%X", id))")
        }

        var sizeRes = try EBMLParser.readElementSize(data: buffer, offset: ro0 + length)
        let headerPayloadSize = try checkedSize(sizeRes.value, context: "ebml.header")
        let headerEnd = length + sizeRes.length + headerPayloadSize
        try advanceBuffer(by: headerEnd)
        AppLog.nativeBridge.notice("[NB-DIAG] demux.ebml.parsed — EBML header \(headerEnd) bytes")

        // 2. Find Segment
        try await ensureBuffer(size: 16)
        let ro1 = bufferReadOffset
        (id, length) = try EBMLParser.readElementID(data: buffer, offset: ro1)
        guard id == EBMLParser.idSegment else {
            AppLog.nativeBridge.error("[NB-DIAG] demux.segment.failed — expected Segment, got \(String(format:"%X", id), privacy: .public)")
            throw NativeBridgeError.invalidMKV("Expected Segment ID, got \(String(format:"%X", id))")
        }

        sizeRes = try EBMLParser.readElementSize(data: buffer, offset: ro1 + length)
        segmentDataSize = sizeRes.value == UInt64.max ? -1 : Int64(sizeRes.value)
        try advanceBuffer(by: length + sizeRes.length)
        segmentDataStart = fileOffset
        AppLog.nativeBridge.notice("[NB-DIAG] demux.segment.found — dataStart=\(self.segmentDataStart) segmentSize=\(self.segmentDataSize)")
        
        // 3. Scan for Info and Tracks close to Segment head to minimize startup latency.
        var foundInfo = false
        var foundTracks = false
        let maxStartupProbeBytes: Int64 = 2 * 1024 * 1024
        
        // Loop until we find both Info and Tracks, or hit a Cluster (which means media data has started)
        while !(foundInfo && foundTracks) {
            if fileOffset - segmentDataStart > maxStartupProbeBytes {
                AppLog.nativeBridge.warning("[NB-DIAG] demux.startup-probe.limit — stopping metadata scan after \(maxStartupProbeBytes) bytes")
                break
            }

            try await ensureBuffer(size: 16)
            let ro = bufferReadOffset
            (id, length) = try EBMLParser.readElementID(data: buffer, offset: ro)

            if id == EBMLParser.idCluster {
                // We reached media payload before finding Tracks/Info. Stop searching.
                break
            }

            sizeRes = try EBMLParser.readElementSize(data: buffer, offset: ro + length)
            let elementSize = try checkedSize(sizeRes.value, context: "segment.child")
            let headerSize = length + sizeRes.length
            let elementTotalSize = try checkedAdd(headerSize, elementSize, context: "segment.child.total")

            if id == EBMLParser.idInfo {
                try await ensureBuffer(size: elementTotalSize)
                let bounds = try checkedSliceBounds(
                    offset: bufferReadOffset,
                    headerSize: headerSize,
                    payloadSize: elementSize,
                    dataCount: buffer.count,
                    context: "segment.info"
                )
                let slice = Data(buffer[bounds.payloadStart..<bounds.payloadEnd])
                try parseInfo(data: slice)
                foundInfo = true
                try advanceBuffer(by: elementTotalSize)
                AppLog.nativeBridge.notice("[NB-DIAG] demux.info.parsed — timecodeScale=\(self.timecodeScale) durationFloat=\(self.durationFloat)")
            } else if id == EBMLParser.idTracks {
                try await ensureBuffer(size: elementTotalSize)
                let bounds = try checkedSliceBounds(
                    offset: bufferReadOffset,
                    headerSize: headerSize,
                    payloadSize: elementSize,
                    dataCount: buffer.count,
                    context: "segment.tracks"
                )
                let slice = Data(buffer[bounds.payloadStart..<bounds.payloadEnd])
                try parseTracks(data: slice)
                foundTracks = true
                try advanceBuffer(by: elementTotalSize)
                AppLog.nativeBridge.notice("[NB-DIAG] demux.tracks.parsed — \(self.parsedTracks.count) tracks found")
                for t in self.parsedTracks {
                    AppLog.nativeBridge.notice("[NB-DIAG]   track \(t.id): type=\(t.trackType.rawValue, privacy: .public) codec=\(t.codecID, privacy: .public) name=\(t.codecName, privacy: .public) cpSize=\(t.codecPrivate?.count ?? 0) \(t.width.map { "\($0)x\(t.height ?? 0)" } ?? "") ch=\(t.channels ?? 0) sr=\(t.sampleRate ?? 0)")
                }
            } else if id == EBMLParser.idCues {
                // Cues can be very large; avoid startup stalls by deferring oversized cue parsing.
                if elementSize <= 256 * 1024 {
                    try await ensureBuffer(size: elementTotalSize)
                    let bounds = try checkedSliceBounds(
                        offset: bufferReadOffset,
                        headerSize: headerSize,
                        payloadSize: elementSize,
                        dataCount: buffer.count,
                        context: "segment.cues"
                    )
                    let slice = Data(buffer[bounds.payloadStart..<bounds.payloadEnd])
                    try parseCues(data: slice)
                    AppLog.nativeBridge.notice("[NB-DIAG] demux.cues.parsed — \(self.extractedCues.count) cue points")
                } else {
                    AppLog.nativeBridge.notice("[NB-DIAG] demux.cues.deferred — size=\(elementSize) bytes")
                }
                try advanceBuffer(by: elementTotalSize)
            } else {
                // Skip other elements (SeekHead, Tags, etc.)
                try await skip(bytes: elementTotalSize)
            }
        }
        
        let durationNs = Int64(durationFloat * Double(timecodeScale))
        
        let info = StreamInfo(
            durationNanoseconds: durationNs > 0 ? durationNs : (7200 * 1_000_000_000), // fallback 2h
            tracks: parsedTracks.isEmpty ? [plan.videoTrack] : parsedTracks,
            hasChapters: false,
            seekable: !extractedCues.isEmpty
        )

        isOpened = true
        AppLog.nativeBridge.notice("[NB-DIAG] demux.open.complete — \(self.parsedTracks.count) tracks, duration=\(durationNs)ns, cues=\(self.extractedCues.count), seekable=\(info.seekable)")
        return info
    }

    public func readPacket() async throws -> DemuxedPacket? {
        guard isOpened else { throw NativeBridgeError.demuxerFailed("Demuxer not opened.") }

        // Drain queued laced packets first
        if !pendingPackets.isEmpty {
            return pendingPackets.removeFirst()
        }

        if eofReached { return nil }
        
        while true {
            try await ensureBuffer(size: 16)
            if buffer.count <= bufferReadOffset {
                eofReached = true
                return nil
            }

            let ro = bufferReadOffset
            let (id, length) = try EBMLParser.readElementID(data: buffer, offset: ro)
            let sizeRes = try EBMLParser.readElementSize(data: buffer, offset: ro + length)
            let headerSize = length + sizeRes.length
            let payloadSize = try checkedSize(sizeRes.value, context: "packet.element")
            let elementTotalSize = try checkedAdd(headerSize, payloadSize, context: "packet.element.total")

            if id == EBMLParser.idCluster {
                clusterEndOffset = sizeRes.value == UInt64.max ? -1 : fileOffset + Int64(elementTotalSize)
                try advanceBuffer(by: headerSize)
                continue
            }

            if id == EBMLParser.idTimecode {
                try await ensureBuffer(size: elementTotalSize)
                currentClusterTimecode = try EBMLParser.readUInt(data: buffer, offset: bufferReadOffset + headerSize, size: payloadSize)
                try advanceBuffer(by: elementTotalSize)
                continue
            }

            if id == EBMLParser.idSimpleBlock {
                try await ensureBuffer(size: elementTotalSize)
                let bounds = try checkedSliceBounds(
                    offset: bufferReadOffset,
                    headerSize: headerSize,
                    payloadSize: payloadSize,
                    dataCount: buffer.count,
                    context: "packet.simpleblock"
                )
                let payloadData = Data(buffer[bounds.payloadStart..<bounds.payloadEnd])
                try advanceBuffer(by: elementTotalSize)
                let packets = try parseSimpleBlock(data: payloadData, clusterTimecode: currentClusterTimecode)
                if !packets.isEmpty {
                    pendingPackets.append(contentsOf: packets.dropFirst())
                    return packets[0]
                }
                continue
            }

            if id == EBMLParser.idBlockGroup {
                try await ensureBuffer(size: elementTotalSize)
                let bounds = try checkedSliceBounds(
                    offset: bufferReadOffset,
                    headerSize: headerSize,
                    payloadSize: payloadSize,
                    dataCount: buffer.count,
                    context: "packet.blockgroup"
                )
                let payloadData = Data(buffer[bounds.payloadStart..<bounds.payloadEnd])
                try advanceBuffer(by: elementTotalSize)
                let packets = try parseBlockGroup(data: payloadData, clusterTimecode: currentClusterTimecode)
                if !packets.isEmpty {
                    pendingPackets.append(contentsOf: packets.dropFirst())
                    return packets[0]
                }
                continue
            }
            
            // Skip unknown elements
            try await skip(bytes: elementTotalSize)
            
            if clusterEndOffset != -1 && fileOffset >= clusterEndOffset {
                clusterEndOffset = -1
            }
        }
    }

    public func readSample() async throws -> Sample? {
        try await readPacket()?.asSample
    }

    public func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        guard isOpened else { throw NativeBridgeError.seekFailed("Demuxer not opened.") }
        
        let targetTimecode = UInt64(timeNanoseconds / Int64(timecodeScale))
        
        // Find the closest (preceding) CuePoint
        if let bestCue = extractedCues.last(where: { $0.timecode <= targetTimecode }) ?? extractedCues.first {
            let absoluteOffset = segmentDataStart + Int64(bestCue.clusterOffset)
            
            AppLog.playback.debug("MatroskaDemuxer: Seeking to timecode \(bestCue.timecode) (offset \(absoluteOffset))")
            
            fileOffset = absoluteOffset
            bufferBase = absoluteOffset
            buffer.removeAll()
            pendingPackets.removeAll()
            eofReached = false
            clusterEndOffset = -1
            currentClusterTimecode = bestCue.timecode

            return Int64(bestCue.timecode) * Int64(timecodeScale)
        } else {
            AppLog.playback.warning("MatroskaDemuxer: No cues parsed. Jumping to beginning of segment.")
            fileOffset = segmentDataStart
            bufferBase = segmentDataStart
            buffer.removeAll()
            pendingPackets.removeAll()
            eofReached = false
            clusterEndOffset = -1
            currentClusterTimecode = 0
            return 0
        }
    }
    
    // MARK: - Private Parsers
    
    private func parseCues(data: Data) throws {
        var offset = 0
        while offset < data.count {
            let (id, length) = try EBMLParser.readElementID(data: data, offset: offset)
            let sizeRes = try EBMLParser.readElementSize(data: data, offset: offset + length)
            let payloadSize = try checkedSize(sizeRes.value, context: "cues.element")
            let headerSize = length + sizeRes.length
            let bounds = try checkedSliceBounds(
                offset: offset,
                headerSize: headerSize,
                payloadSize: payloadSize,
                dataCount: data.count,
                context: "cues"
            )
            
            if id == EBMLParser.idCuePoint {
                let cueData = Data(data[bounds.payloadStart..<bounds.payloadEnd])
                if let cue = try parseCuePoint(data: cueData) {
                    extractedCues.append(cue)
                }
            }
            offset = bounds.nextOffset
        }
    }
    
    private func parseCuePoint(data: Data) throws -> CuePoint? {
        var offset = 0
        var cueTime: UInt64 = 0
        var clusterOffset: UInt64? = nil
        var cueTrackNumber: UInt64?
        
        while offset < data.count {
            let (id, length) = try EBMLParser.readElementID(data: data, offset: offset)
            let sizeRes = try EBMLParser.readElementSize(data: data, offset: offset + length)
            let headerSize = length + sizeRes.length
            let payloadSize = try checkedSize(sizeRes.value, context: "cue.point")
            let bounds = try checkedSliceBounds(
                offset: offset,
                headerSize: headerSize,
                payloadSize: payloadSize,
                dataCount: data.count,
                context: "cue.point"
            )
            let payloadOffset = bounds.payloadStart
            
            if id == EBMLParser.idCueTime {
                cueTime = try EBMLParser.readUInt(data: data, offset: payloadOffset, size: payloadSize)
            } else if id == EBMLParser.idCueTrackPositions {
                var tpOffset = payloadOffset
                let tpEnd = bounds.payloadEnd
                while tpOffset < tpEnd {
                    let (tpid, tplen) = try EBMLParser.readElementID(data: data, offset: tpOffset)
                    let tpsizeRes = try EBMLParser.readElementSize(data: data, offset: tpOffset + tplen)
                    let tphdrSize = tplen + tpsizeRes.length
                    let tppaySize = try checkedSize(tpsizeRes.value, context: "cue.track.positions")
                    let tpBounds = try checkedSliceBounds(
                        offset: tpOffset,
                        headerSize: tphdrSize,
                        payloadSize: tppaySize,
                        dataCount: data.count,
                        context: "cue.track.positions"
                    )
                    
                    if tpid == EBMLParser.idCueTrack {
                        cueTrackNumber = try EBMLParser.readUInt(
                            data: data,
                            offset: tpOffset + tphdrSize,
                            size: tppaySize
                        )
                    } else if tpid == EBMLParser.idCueClusterPosition {
                        clusterOffset = try EBMLParser.readUInt(data: data, offset: tpOffset + tphdrSize, size: tppaySize)
                    }
                    tpOffset = tpBounds.nextOffset
                }
            }
            offset = bounds.nextOffset
        }

        if let cueTrackNumber, cueTrackNumber != UInt64(plan.videoTrack.id) {
            return nil
        }
        if let clusterOffset = clusterOffset {
            return CuePoint(timecode: cueTime, clusterOffset: clusterOffset)
        }
        return nil
    }
    
    private func parseInfo(data: Data) throws {
        var offset = 0
        while offset < data.count {
            let (id, length) = try EBMLParser.readElementID(data: data, offset: offset)
            let sizeRes = try EBMLParser.readElementSize(data: data, offset: offset + length)
            let payloadSize = try checkedSize(sizeRes.value, context: "info.element")
            let headerSize = length + sizeRes.length
            let bounds = try checkedSliceBounds(
                offset: offset,
                headerSize: headerSize,
                payloadSize: payloadSize,
                dataCount: data.count,
                context: "info"
            )
            
            if id == EBMLParser.idTimecodeScale {
                timecodeScale = try EBMLParser.readUInt(data: data, offset: offset + headerSize, size: payloadSize)
            } else if id == EBMLParser.idDuration {
                durationFloat = try EBMLParser.readFloat(data: data, offset: offset + headerSize, size: payloadSize)
            }
            
            offset = bounds.nextOffset
        }
    }
    
    private func parseTracks(data: Data) throws {
        var offset = 0
        while offset < data.count {
            let (id, length) = try EBMLParser.readElementID(data: data, offset: offset)
            let sizeRes = try EBMLParser.readElementSize(data: data, offset: offset + length)
            let payloadSize = try checkedSize(sizeRes.value, context: "tracks.element")
            let headerSize = length + sizeRes.length
            let bounds = try checkedSliceBounds(
                offset: offset,
                headerSize: headerSize,
                payloadSize: payloadSize,
                dataCount: data.count,
                context: "tracks"
            )
            
            if id == EBMLParser.idTrackEntry {
                let trackData = Data(data[bounds.payloadStart..<bounds.payloadEnd])
                if let track = try parseTrackEntry(data: trackData) {
                    parsedTracks.append(track)
                }
            }
            
            offset = bounds.nextOffset
        }
    }
    
    private func parseTrackEntry(data: Data) throws -> TrackInfo? {
        var offset = 0

        var trackNumber: UInt64 = 0
        var trackTypeVal: UInt64 = 0
        var codecID = ""
        var codecPrivate: Data? = nil
        var defaultDurationNs: UInt64? = nil
        var language: String? = nil
        var isDefault = false
        var isForced = false

        var width: Int?
        var height: Int?
        var channels: Int?
        var sampleRate: Int?
        var bitDepth: Int?

        var transferCharacteristic: Int?
        var colourPrimaries: Int?
        var matrixCoefficients: Int?
        var videoBitDepth: Int?
        var maxCLL: Int?
        var maxFALL: Int?
        var masteringLuminanceMax: Double? = nil
        var masteringLuminanceMin: Double? = nil

        while offset < data.count {
            let (id, length) = try EBMLParser.readElementID(data: data, offset: offset)
            let sizeRes = try EBMLParser.readElementSize(data: data, offset: offset + length)
            let payloadSize = try checkedSize(sizeRes.value, context: "track.entry")
            let headerSize = length + sizeRes.length
            let bounds = try checkedSliceBounds(
                offset: offset,
                headerSize: headerSize,
                payloadSize: payloadSize,
                dataCount: data.count,
                context: "track.entry"
            )
            let payloadOffset = bounds.payloadStart

            switch id {
            case EBMLParser.idTrackNumber:
                trackNumber = try EBMLParser.readUInt(data: data, offset: payloadOffset, size: payloadSize)
            case EBMLParser.idTrackType:
                trackTypeVal = try EBMLParser.readUInt(data: data, offset: payloadOffset, size: payloadSize)
            case EBMLParser.idCodecID:
                codecID = try EBMLParser.readString(data: data, offset: payloadOffset, size: payloadSize)
            case EBMLParser.idCodecPrivate:
                codecPrivate = Data(data[payloadOffset..<payloadOffset+payloadSize])
            case EBMLParser.idDefaultDuration:
                defaultDurationNs = try EBMLParser.readUInt(data: data, offset: payloadOffset, size: payloadSize)
            case EBMLParser.idLanguage:
                language = try EBMLParser.readString(data: data, offset: payloadOffset, size: payloadSize)
            case EBMLParser.idFlagDefault:
                isDefault = (try EBMLParser.readUInt(data: data, offset: payloadOffset, size: payloadSize)) != 0
            case EBMLParser.idFlagForced:
                isForced = (try EBMLParser.readUInt(data: data, offset: payloadOffset, size: payloadSize)) != 0
            case EBMLParser.idVideo:
                var vOffset = payloadOffset
                let vEnd = payloadOffset + payloadSize
                while vOffset < vEnd {
                    let (vid, vlen) = try EBMLParser.readElementID(data: data, offset: vOffset)
                    let vsizeRes = try EBMLParser.readElementSize(data: data, offset: vOffset + vlen)
                    let vhdrSize = vlen + vsizeRes.length
                    let vpaySize = try checkedSize(vsizeRes.value, context: "track.video")

                    if vid == EBMLParser.idPixelWidth {
                        width = Int(try EBMLParser.readUInt(data: data, offset: vOffset + vhdrSize, size: vpaySize))
                    } else if vid == EBMLParser.idPixelHeight {
                        height = Int(try EBMLParser.readUInt(data: data, offset: vOffset + vhdrSize, size: vpaySize))
                    } else if vid == EBMLParser.idColour {
                        var cOffset = vOffset + vhdrSize
                        let cEnd = cOffset + vpaySize
                        while cOffset < cEnd {
                            let (cid, clen) = try EBMLParser.readElementID(data: data, offset: cOffset)
                            let csizeRes = try EBMLParser.readElementSize(data: data, offset: cOffset + clen)
                            let chdrSize = clen + csizeRes.length
                            let cpaySize = try checkedSize(csizeRes.value, context: "track.colour")

                            switch cid {
                            case EBMLParser.idMatrixCoefficients:
                                matrixCoefficients = Int(try EBMLParser.readUInt(data: data, offset: cOffset + chdrSize, size: cpaySize))
                            case EBMLParser.idBitsPerChannel:
                                videoBitDepth = Int(try EBMLParser.readUInt(data: data, offset: cOffset + chdrSize, size: cpaySize))
                            case EBMLParser.idTransferCharacteristics:
                                transferCharacteristic = Int(try EBMLParser.readUInt(data: data, offset: cOffset + chdrSize, size: cpaySize))
                            case EBMLParser.idPrimaries:
                                colourPrimaries = Int(try EBMLParser.readUInt(data: data, offset: cOffset + chdrSize, size: cpaySize))
                            case EBMLParser.idMaxCLL:
                                maxCLL = Int(try EBMLParser.readUInt(data: data, offset: cOffset + chdrSize, size: cpaySize))
                            case EBMLParser.idMaxFALL:
                                maxFALL = Int(try EBMLParser.readUInt(data: data, offset: cOffset + chdrSize, size: cpaySize))
                            case EBMLParser.idMasteringMetadata:
                                // Parse mastering display metadata sub-elements
                                var mOffset = cOffset + chdrSize
                                let mEnd = mOffset + cpaySize
                                while mOffset < mEnd {
                                    let (mid, mlen) = try EBMLParser.readElementID(data: data, offset: mOffset)
                                    let msizeRes = try EBMLParser.readElementSize(data: data, offset: mOffset + mlen)
                                    let mhdrSize = mlen + msizeRes.length
                                    let mpaySize = try checkedSize(msizeRes.value, context: "track.mastering")
                                    switch mid {
                                    case EBMLParser.idMasteringLuminanceMax:
                                        masteringLuminanceMax = try EBMLParser.readFloat(data: data, offset: mOffset + mhdrSize, size: mpaySize)
                                    case EBMLParser.idMasteringLuminanceMin:
                                        masteringLuminanceMin = try EBMLParser.readFloat(data: data, offset: mOffset + mhdrSize, size: mpaySize)
                                    default:
                                        break
                                    }
                                    mOffset += mhdrSize + mpaySize
                                }
                            default:
                                break
                            }
                            cOffset += chdrSize + cpaySize
                        }
                    }
                    vOffset += vhdrSize + vpaySize
                }
            case EBMLParser.idAudio:
                var aOffset = payloadOffset
                let aEnd = payloadOffset + payloadSize
                while aOffset < aEnd {
                    let (aid, alen) = try EBMLParser.readElementID(data: data, offset: aOffset)
                    let asizeRes = try EBMLParser.readElementSize(data: data, offset: aOffset + alen)
                    let ahdrSize = alen + asizeRes.length
                    let apaySize = try checkedSize(asizeRes.value, context: "track.audio")

                    if aid == EBMLParser.idChannels {
                        channels = Int(try EBMLParser.readUInt(data: data, offset: aOffset + ahdrSize, size: apaySize))
                    } else if aid == EBMLParser.idSamplingFrequency {
                        sampleRate = Int(try EBMLParser.readFloat(data: data, offset: aOffset + ahdrSize, size: apaySize))
                    } else if aid == EBMLParser.idBitDepth {
                        bitDepth = Int(try EBMLParser.readUInt(data: data, offset: aOffset + ahdrSize, size: apaySize))
                    }
                    aOffset += ahdrSize + apaySize
                }
            default:
                break
            }

            offset = bounds.nextOffset
        }

        let trackType: TrackInfo.TrackType
        if trackTypeVal == 1 { trackType = .video }
        else if trackTypeVal == 2 { trackType = .audio }
        else if trackTypeVal == 0x11 { trackType = .subtitle }
        else { return nil }

        // Map MKV CodecID to internal representation
        let codecName: String
        let lower = codecID.lowercased()
        if lower.contains("hevc") { codecName = "hevc" }
        else if lower.contains("avc") { codecName = "h264" }
        else if lower.contains("aac") { codecName = "aac" }
        else if lower.contains("eac3") || lower == "a_eac3" { codecName = "eac3" }
        else if lower.contains("ac3") { codecName = "ac3" }
        else { codecName = lower.replacingOccurrences(of: "v_mpeg4/iso/", with: "").replacingOccurrences(of: "a_", with: "") }

        let trackNum = try checkedSize(trackNumber, context: "track.number")

        // Store default duration for use during packet reading
        if let dur = defaultDurationNs {
            trackDefaultDurations[trackNum] = Int64(dur)
        }

        // For video tracks, prefer BitsPerChannel from Colour element; for audio, use audio BitDepth
        let effectiveBitDepth = (trackType == .video) ? (videoBitDepth ?? bitDepth) : bitDepth

        let subtitleHandling: SubtitleHandling? = (trackType == .subtitle) ? SubtitleHandling.classify(codecName) : nil
        let subtitleKind: SubtitleKind?
        switch subtitleHandling {
        case .textExternal:
            subtitleKind = .text
        case .bitmapBurnIn:
            subtitleKind = .bitmap
        case .unsupported, .none:
            subtitleKind = (trackType == .subtitle) ? .unknown : nil
        }

        let audioSupport: AudioCodecSupport? = (trackType == .audio) ? AudioCodecSupport.classify(codecName) : nil

        return TrackInfo(
            id: trackNum,
            trackType: trackType,
            codecID: codecID,
            codecName: codecName,
            language: language,
            isDefault: isDefault,
            isForced: isForced,
            width: width,
            height: height,
            bitDepth: effectiveBitDepth,
            codecPrivate: codecPrivate,
            colourPrimaries: colourPrimaries,
            transferCharacteristic: transferCharacteristic,
            matrixCoefficients: matrixCoefficients,
            maxCLL: maxCLL,
            maxFALL: maxFALL,
            masteringLuminanceMax: masteringLuminanceMax,
            masteringLuminanceMin: masteringLuminanceMin,
            sampleRate: sampleRate,
            channels: channels,
            audioSupport: audioSupport,
            subtitleHandling: subtitleHandling,
            subtitleKind: subtitleKind,
            metadataConfidence: .demux
        )
    }
    
    /// Parses a SimpleBlock or Block header. Returns track info, timing, keyframe, and one or more payloads (multiple if laced).
    private func parseBlockHeader(
        data: Data,
        clusterTimecode: UInt64,
        isSimpleBlock: Bool
    ) throws -> (trackID: Int, timestampNs: Int64, isKeyframe: Bool, payloads: [Data])? {
        guard data.count > 4 else { return nil }

        // Block/SimpleBlock header: TrackNumber (VINT), Timecode (Int16 BE), Flags (UInt8)
        let trackNum = try EBMLParser.readElementSize(data: data, offset: 0)
        let trackNumLength = trackNum.length
        guard trackNumLength > 0 else {
            throw NativeBridgeError.invalidMKV("Invalid track number VINT")
        }
        let trackNumber = try checkedSize(trackNum.value, context: "block.track.number")

        guard trackNumber == plan.videoTrack.id || trackNumber == plan.audioTrack?.id else {
            return nil
        }

        let headerSize = trackNumLength + 3
        guard headerSize <= data.count else {
            throw NativeBridgeError.invalidMKV("Malformed block header size")
        }

        let timecodeOffset = trackNumLength
        let blockTimecodeInt16 = Int16(bitPattern: UInt16(data[timecodeOffset]) << 8 | UInt16(data[timecodeOffset + 1]))
        let flags = data[timecodeOffset + 2]
        // For SimpleBlock, bit 7 of flags = keyframe; for Block inside BlockGroup, keyframe = no ReferenceBlock
        let isKeyframe = isSimpleBlock ? (flags & 0x80) != 0 : false

        let lacingMode = (flags >> 1) & 0x03  // bits 1-2: 0=none, 1=Xiph, 2=fixed, 3=EBML
        let rawPayload = Data(data[headerSize...])

        let absoluteTimecode = Int64(clusterTimecode) + Int64(blockTimecodeInt16)
        let timestampNs = absoluteTimecode * Int64(timecodeScale)

        let payloads: [Data]
        if lacingMode == 0 {
            payloads = [rawPayload]
        } else {
            payloads = try parseLacedFrames(data: rawPayload, lacingMode: lacingMode)
        }

        return (trackNumber, timestampNs, isKeyframe, payloads)
    }

    /// Splits laced block data into individual frames.
    private func parseLacedFrames(data: Data, lacingMode: UInt8) throws -> [Data] {
        guard data.count >= 1 else { return [data] }

        let frameCount = Int(data[0]) + 1
        guard frameCount > 1 else { return [Data(data[1...])] }

        var offset = 1

        if lacingMode == 2 {
            // Fixed-size lacing: all frames are equal size
            let remainingBytes = data.count - offset
            let frameSize = remainingBytes / frameCount
            var frames: [Data] = []
            for _ in 0..<frameCount {
                guard offset + frameSize <= data.count else { break }
                frames.append(Data(data[offset..<offset + frameSize]))
                offset += frameSize
            }
            return frames
        }

        // Xiph (1) or EBML (3) lacing: read frame sizes for all frames except the last
        var frameSizes: [Int] = []
        for i in 0..<(frameCount - 1) {
            if lacingMode == 1 {
                // Xiph lacing: sum of consecutive 255 bytes until < 255
                var size = 0
                while offset < data.count {
                    let byte = Int(data[offset])
                    offset += 1
                    size += byte
                    if byte < 255 { break }
                }
                frameSizes.append(size)
            } else {
                // EBML lacing: first size is VINT, subsequent are signed delta VINTs
                if i == 0 {
                    let vint = try EBMLParser.readElementSize(data: data, offset: offset)
                    frameSizes.append(try checkedSize(vint.value, context: "ebml.lacing.first"))
                    offset += vint.length
                } else {
                    // Signed VINT delta
                    let vint = try EBMLParser.readElementSize(data: data, offset: offset)
                    guard vint.value <= UInt64(Int64.max) else {
                        throw NativeBridgeError.invalidMKV("EBML lacing delta too large")
                    }
                    let raw = Int64(vint.value)
                    // Decode signed: subtract the midpoint for the VINT length
                    let midpoint: Int64
                    switch vint.length {
                    case 1: midpoint = 0x3F
                    case 2: midpoint = 0x1FFF
                    case 3: midpoint = 0x0FFFFF
                    case 4: midpoint = 0x07FFFFFF
                    default: midpoint = 0x3F
                    }
                    let delta = raw - midpoint
                    let prevSize = frameSizes.last ?? 0
                    guard delta >= Int64(-prevSize) else {
                        throw NativeBridgeError.invalidMKV("Negative EBML lacing frame size")
                    }
                    frameSizes.append(prevSize + Int(delta))
                    offset += vint.length
                }
            }
        }

        // Last frame gets the remaining bytes
        let usedByFrames = frameSizes.reduce(0, +)
        let lastSize = data.count - offset - usedByFrames
        frameSizes.append(max(0, lastSize))

        var frames: [Data] = []
        for size in frameSizes {
            guard offset + size <= data.count else { break }
            frames.append(Data(data[offset..<offset + size]))
            offset += size
        }
        return frames
    }

    private func parseSimpleBlock(data: Data, clusterTimecode: UInt64) throws -> [DemuxedPacket] {
        guard let parsed = try parseBlockHeader(data: data, clusterTimecode: clusterTimecode, isSimpleBlock: true) else {
            return []
        }
        let durationNs = trackDefaultDurations[parsed.trackID] ?? 33_333_333
        return parsed.payloads.enumerated().map { index, payload in
            DemuxedPacket(
                trackID: parsed.trackID,
                timestamp: parsed.timestampNs + Int64(index) * durationNs,
                duration: durationNs,
                isKeyframe: index == 0 ? parsed.isKeyframe : false,
                data: payload
            )
        }
    }

    /// Parses a BlockGroup element (contains Block + optional BlockDuration + optional ReferenceBlock).
    private func parseBlockGroup(data: Data, clusterTimecode: UInt64) throws -> [DemuxedPacket] {
        var offset = 0
        var blockData: Data? = nil
        var blockDurationNs: Int64? = nil
        var hasReferenceBlock = false

        while offset < data.count {
            let (id, length) = try EBMLParser.readElementID(data: data, offset: offset)
            let sizeRes = try EBMLParser.readElementSize(data: data, offset: offset + length)
            let payloadSize = try checkedSize(sizeRes.value, context: "block.group")
            let headerSize = length + sizeRes.length
            let bounds = try checkedSliceBounds(
                offset: offset,
                headerSize: headerSize,
                payloadSize: payloadSize,
                dataCount: data.count,
                context: "block.group"
            )

            if id == EBMLParser.idBlock {
                blockData = Data(data[bounds.payloadStart..<bounds.payloadEnd])
            } else if id == EBMLParser.idBlockDuration {
                let rawDuration = try EBMLParser.readUInt(data: data, offset: offset + headerSize, size: payloadSize)
                // BlockDuration is in TimecodeScale units
                blockDurationNs = Int64(rawDuration) * Int64(timecodeScale)
            } else if id == EBMLParser.idReferenceBlock {
                hasReferenceBlock = true
            }
            offset = bounds.nextOffset
        }

        guard let block = blockData else { return [] }

        // Parse the Block header (same format as SimpleBlock minus the keyframe flag in flags byte)
        guard let parsed = try parseBlockHeader(data: block, clusterTimecode: clusterTimecode, isSimpleBlock: false) else {
            return []
        }

        // Keyframe = absence of ReferenceBlock in the BlockGroup
        let isKeyframe = !hasReferenceBlock
        let frameDurationNs: Int64
        if let blockDur = blockDurationNs {
            frameDurationNs = blockDur / Int64(max(1, parsed.payloads.count))
        } else {
            frameDurationNs = trackDefaultDurations[parsed.trackID] ?? 33_333_333
        }

        return parsed.payloads.enumerated().map { index, payload in
            DemuxedPacket(
                trackID: parsed.trackID,
                timestamp: parsed.timestampNs + Int64(index) * frameDurationNs,
                duration: frameDurationNs,
                isKeyframe: index == 0 ? isKeyframe : false,
                data: payload
            )
        }
    }
    
    // MARK: - Buffer Management
    
    private func ensureBuffer(size: Int) async throws {
        while buffer.count - bufferReadOffset < size {
            // Read at the end of what is already buffered (bufferBase + full buffer length)
            let chunk = try await reader.read(offset: bufferBase + Int64(buffer.count), length: 65536)
            if chunk.isEmpty {
                if buffer.count - bufferReadOffset < size { throw NativeBridgeError.demuxerEOF }
                break
            }
            buffer.append(chunk)
        }
    }

    private func advanceBuffer(by count: Int) throws {
        guard count >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative advance count \(count)")
        }
        guard count <= buffer.count - bufferReadOffset else {
            throw NativeBridgeError.demuxerFailed("Advance past buffer length")
        }
        if count == 0 { return }
        // Advance read head without touching the buffer bytes.
        fileOffset += Int64(count)
        // Periodic compaction: trim dead bytes when the dead zone exceeds 256 KB.
        let ro = bufferReadOffset
        if ro > 256 * 1024 {
            buffer = Data(buffer[ro...])
            bufferBase = fileOffset  // buffer[0] now corresponds to the new read head
        }
    }

    private func skip(bytes: Int) async throws {
        guard bytes >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative skip bytes \(bytes)")
        }
        if bytes <= buffer.count - bufferReadOffset {
            try advanceBuffer(by: bytes)
        } else {
            fileOffset += Int64(bytes)
            bufferBase = fileOffset
            buffer.removeAll()
            let chunk = try await reader.read(offset: fileOffset, length: 1)
            buffer.append(chunk)
        }
    }

    private func checkedSize(_ raw: UInt64, context: String) throws -> Int {
        if raw == UInt64.max {
            throw NativeBridgeError.invalidMKV("Unsupported unknown element size in \(context)")
        }
        guard raw <= UInt64(Int.max) else {
            throw NativeBridgeError.invalidMKV("Element too large in \(context): \(raw)")
        }
        return Int(raw)
    }

    private func checkedAdd(_ lhs: Int, _ rhs: Int, context: String) throws -> Int {
        guard lhs >= 0, rhs >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative arithmetic input in \(context)")
        }
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow {
            throw NativeBridgeError.invalidMKV("Integer overflow in \(context)")
        }
        return sum
    }

    private func checkedSliceBounds(
        offset: Int,
        headerSize: Int,
        payloadSize: Int,
        dataCount: Int,
        context: String
    ) throws -> (payloadStart: Int, payloadEnd: Int, nextOffset: Int) {
        let payloadStart = try checkedAdd(offset, headerSize, context: "\(context).payloadStart")
        let payloadEnd = try checkedAdd(payloadStart, payloadSize, context: "\(context).payloadEnd")
        guard payloadEnd <= dataCount else {
            throw NativeBridgeError.demuxerEOF
        }
        return (payloadStart, payloadEnd, payloadEnd)
    }
}

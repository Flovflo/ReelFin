import CoreMedia
import Foundation

public struct MatroskaClusterParser: Sendable {
    private let reader = EBMLReader()

    public init() {}

    public func parseCluster(
        data: Data,
        header: EBMLElementHeader,
        timecodeScale: Int64,
        trackDefaultDurations: [Int: CMTime] = [:]
    ) throws -> [MediaPacket] {
        var packets: [MediaPacket] = []
        var clusterTimecode: Int64 = 0
        var offset = header.payloadOffset
        while offset < payloadEnd(header) {
            let child = try reader.readHeader(data: data, offset: offset)
            if child.id == EBMLElementID.timecode {
                clusterTimecode = Int64(try reader.readUInt(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0)))
            } else if child.id == EBMLElementID.simpleBlock {
                let blockData = Data(data[child.payloadOffset..<payloadEnd(child)])
                let blocks = try parseBlocks(blockData, explicitKeyframe: nil)
                packets.append(
                    contentsOf: makePackets(
                        from: blocks,
                        clusterTimecode: clusterTimecode,
                        timecodeScale: timecodeScale,
                        trackDefaultDurations: trackDefaultDurations
                    )
                )
            } else if child.id == EBMLElementID.blockGroup {
                packets.append(
                    contentsOf: try parseBlockGroup(
                        data: data,
                        header: child,
                        clusterTimecode: clusterTimecode,
                        timecodeScale: timecodeScale,
                        trackDefaultDurations: trackDefaultDurations
                    )
                )
            }
            offset = payloadEnd(child)
        }
        return packets
    }

    public func parseBlock(_ data: Data, explicitKeyframe: Bool?) throws -> MatroskaParsedBlock {
        guard let block = try parseBlocks(data, explicitKeyframe: explicitKeyframe).first else {
            throw EBMLError.invalidMatroska("empty block")
        }
        return block
    }

    public func parseBlocks(_ data: Data, explicitKeyframe: Bool?) throws -> [MatroskaParsedBlock] {
        let track = try reader.readElementSize(data: data, offset: 0)
        guard let trackNumber = track.value, data.count >= track.length + 3 else {
            throw EBMLError.invalidMatroska("malformed block header")
        }
        let timeOffset = track.length
        let rawTime = UInt16(data[timeOffset]) << 8 | UInt16(data[timeOffset + 1])
        let flags = data[timeOffset + 2]
        let keyframe = explicitKeyframe ?? ((flags & 0x80) != 0)
        let invisible = (flags & 0x08) != 0
        let lacing = (flags >> 1) & 0x03
        let payloadOffset = timeOffset + 3
        return try payloads(from: data, offset: payloadOffset, lacing: lacing).map {
            MatroskaParsedBlock(
                trackNumber: Int(trackNumber),
                relativeTimecode: Int16(bitPattern: rawTime),
                keyframe: keyframe,
                invisible: invisible,
                payload: $0
            )
        }
    }

    private func parseBlockGroup(
        data: Data,
        header: EBMLElementHeader,
        clusterTimecode: Int64,
        timecodeScale: Int64,
        trackDefaultDurations: [Int: CMTime]
    ) throws -> [MediaPacket] {
        var blocks: [MatroskaParsedBlock] = []
        var hasReferenceBlock = false
        var blockDuration: CMTime?
        var offset = header.payloadOffset
        while offset < payloadEnd(header) {
            let child = try reader.readHeader(data: data, offset: offset)
            if child.id == EBMLElementID.block {
                blocks = try parseBlocks(Data(data[child.payloadOffset..<payloadEnd(child)]), explicitKeyframe: nil)
            } else if child.id == EBMLElementID.blockDuration {
                let rawDuration = try reader.readUInt(
                    data: data,
                    offset: child.payloadOffset,
                    size: Int(child.size ?? 0)
                )
                blockDuration = CMTime(value: Int64(rawDuration) * timecodeScale, timescale: 1_000_000_000)
            } else if child.id == EBMLElementID.referenceBlock {
                hasReferenceBlock = true
            }
            offset = payloadEnd(child)
        }
        guard !blocks.isEmpty else { return [] }
        let explicitDurations = blocks.first.map { block -> [Int: CMTime] in
            guard let blockDuration else { return trackDefaultDurations }
            var durations = trackDefaultDurations
            durations[block.trackNumber] = blockDuration
            return durations
        } ?? trackDefaultDurations
        let keyedBlocks = blocks.map { block in
            var adjusted = block
            adjusted.keyframe = !hasReferenceBlock
            return adjusted
        }
        return makePackets(
            from: keyedBlocks,
            clusterTimecode: clusterTimecode,
            timecodeScale: timecodeScale,
            trackDefaultDurations: explicitDurations
        )
    }

    private func makePackets(
        from blocks: [MatroskaParsedBlock],
        clusterTimecode: Int64,
        timecodeScale: Int64,
        trackDefaultDurations: [Int: CMTime]
    ) -> [MediaPacket] {
        var laceIndexesByTrack: [Int: Int32] = [:]
        return blocks.map { block in
            var packet = packet(from: block, clusterTimecode: clusterTimecode, timecodeScale: timecodeScale)
            guard let duration = trackDefaultDurations[block.trackNumber] else { return packet }
            let laceIndex = laceIndexesByTrack[block.trackNumber, default: 0]
            laceIndexesByTrack[block.trackNumber] = laceIndex + 1
            packet.timestamp.pts = packet.timestamp.pts + CMTimeMultiply(duration, multiplier: laceIndex)
            packet.timestamp.duration = packet.timestamp.duration ?? duration
            return packet
        }
    }

    private func payloads(from data: Data, offset: Int, lacing: UInt8) throws -> [Data] {
        switch lacing {
        case 0:
            return [Data(data[offset..<data.count])]
        case 1:
            return try xiphLacedPayloads(from: data, offset: offset)
        case 2:
            return try fixedSizeLacedPayloads(from: data, offset: offset)
        case 3:
            return try ebmlLacedPayloads(from: data, offset: offset)
        default:
            throw EBMLError.invalidMatroska("unknown Matroska lacing mode \(lacing)")
        }
    }

    private func xiphLacedPayloads(from data: Data, offset: Int) throws -> [Data] {
        guard offset < data.count else { throw EBMLError.invalidMatroska("missing Xiph lace count") }
        let frameCount = Int(data[offset]) + 1
        var cursor = offset + 1
        var frameSizes: [Int] = []
        for _ in 0..<(frameCount - 1) {
            var size = 0
            while true {
                guard cursor < data.count else { throw EBMLError.invalidMatroska("truncated Xiph lace size") }
                let byte = Int(data[cursor])
                cursor += 1
                size += byte
                if byte != 255 { break }
            }
            frameSizes.append(size)
        }
        return try splitLacedPayload(data: data, payloadOffset: cursor, frameSizes: frameSizes, frameCount: frameCount)
    }

    private func fixedSizeLacedPayloads(from data: Data, offset: Int) throws -> [Data] {
        guard offset < data.count else { throw EBMLError.invalidMatroska("missing fixed-size lace count") }
        let frameCount = Int(data[offset]) + 1
        let payloadOffset = offset + 1
        let remaining = data.count - payloadOffset
        guard frameCount > 0, remaining >= 0, remaining % frameCount == 0 else {
            throw EBMLError.invalidMatroska("fixed-size laced block payload is not evenly divisible")
        }
        return try splitLacedPayload(
            data: data,
            payloadOffset: payloadOffset,
            frameSizes: Array(repeating: remaining / frameCount, count: frameCount),
            frameCount: frameCount,
            hasFinalImplicitSize: false
        )
    }

    private func ebmlLacedPayloads(from data: Data, offset: Int) throws -> [Data] {
        guard offset < data.count else { throw EBMLError.invalidMatroska("missing EBML lace count") }
        let frameCount = Int(data[offset]) + 1
        guard frameCount > 1 else { throw EBMLError.invalidMatroska("EBML lacing requires at least two frames") }
        var cursor = offset + 1
        let first = try reader.readElementSize(data: data, offset: cursor)
        guard let firstSize = first.value, firstSize >= 0 else {
            throw EBMLError.invalidMatroska("invalid first EBML laced frame size")
        }
        cursor += first.length
        var previousSize = Int(firstSize)
        var frameSizes = [previousSize]

        for _ in 0..<(frameCount - 2) {
            let delta = try readSignedLaceSize(data, cursor: &cursor)
            let nextSize = previousSize + delta
            guard nextSize >= 0 else {
                throw EBMLError.invalidMatroska("negative EBML laced frame size")
            }
            frameSizes.append(nextSize)
            previousSize = nextSize
        }

        return try splitLacedPayload(data: data, payloadOffset: cursor, frameSizes: frameSizes, frameCount: frameCount)
    }

    private func splitLacedPayload(
        data: Data,
        payloadOffset: Int,
        frameSizes explicitSizes: [Int],
        frameCount: Int,
        hasFinalImplicitSize: Bool = true
    ) throws -> [Data] {
        let explicitTotal = explicitSizes.reduce(0, +)
        let remaining = data.count - payloadOffset
        guard remaining >= explicitTotal else {
            throw EBMLError.invalidMatroska("laced frame sizes exceed block payload")
        }
        let frameSizes = hasFinalImplicitSize
            ? explicitSizes + [remaining - explicitTotal]
            : explicitSizes
        guard frameSizes.count == frameCount else {
            throw EBMLError.invalidMatroska("laced frame count does not match frame sizes")
        }
        var cursor = payloadOffset
        return try frameSizes.map { size in
            guard size >= 0, cursor + size <= data.count else {
                throw EBMLError.invalidMatroska("laced frame extends past block payload")
            }
            defer { cursor += size }
            return Data(data[cursor..<cursor + size])
        }
    }

    private func packet(from block: MatroskaParsedBlock, clusterTimecode: Int64, timecodeScale: Int64) -> MediaPacket {
        let scaled = (clusterTimecode + Int64(block.relativeTimecode)) * timecodeScale
        let pts = CMTime(value: scaled, timescale: 1_000_000_000)
        return MediaPacket(
            trackID: block.trackNumber,
            timestamp: PacketTimestamp(pts: pts),
            isKeyframe: block.keyframe,
            data: block.payload
        )
    }


    private func payloadEnd(_ header: EBMLElementHeader) -> Int {
        header.payloadOffset + Int(header.size ?? 0)
    }

    private func readSignedLaceSize(_ data: Data, cursor: inout Int) throws -> Int {
        let value = try reader.readElementSize(data: data, offset: cursor)
        guard let unsigned = value.value else {
            throw EBMLError.invalidMatroska("unknown-sized EBML lace delta")
        }
        cursor += value.length
        let bits = 7 * value.length
        let bias = (Int64(1) << Int64(bits - 1)) - 1
        return Int(unsigned - bias)
    }
}

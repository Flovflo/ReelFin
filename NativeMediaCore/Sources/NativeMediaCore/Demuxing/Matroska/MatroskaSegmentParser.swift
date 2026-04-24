import CoreMedia
import Foundation

public struct MatroskaSegmentParser: Sendable {
    private let reader = EBMLReader()
    private let trackParser = MatroskaTrackParser()
    private let cueParser = MatroskaCueParser()
    private let clusterParser = MatroskaClusterParser()

    public init() {}

    public func parse(data: Data) throws -> MatroskaSegment {
        var offset = 0
        let ebml = try reader.readHeader(data: data, offset: offset)
        guard ebml.id == EBMLElementID.ebml else { throw EBMLError.invalidMatroska("missing EBML header") }
        offset = payloadEnd(ebml)
        let segmentHeader = try reader.readHeader(data: data, offset: offset)
        guard segmentHeader.id == EBMLElementID.segment else { throw EBMLError.invalidMatroska("missing Segment") }
        return try parseSegmentBody(data: data, segmentHeader: segmentHeader)
    }

    private func parseSegmentBody(data: Data, segmentHeader: EBMLElementHeader) throws -> MatroskaSegment {
        var segment = MatroskaSegment()
        segment.segmentPayloadOffset = segmentHeader.payloadOffset
        var offset = segmentHeader.payloadOffset
        let end = segmentHeader.size.map { min(data.count, segmentHeader.payloadOffset + Int($0)) } ?? data.count
        segment.segmentEndOffset = segmentHeader.size.map { segmentHeader.payloadOffset + Int($0) }
        segment.parsedUntilOffset = offset
        while offset < end {
            let child = try reader.readHeader(data: data, offset: offset)
                let childEnd = payloadEnd(child, defaultEnd: end)
            guard childEnd <= data.count else {
                if child.id == EBMLElementID.cluster {
                    if segment.firstClusterOffset == nil {
                        segment.firstClusterOffset = offset
                    }
                    segment.clusterRanges.append(
                        MatroskaClusterRange(offset: offset, payloadOffset: child.payloadOffset, endOffset: childEnd)
                    )
                }
                segment.parsedUntilOffset = offset
                break
            }
            if child.id == EBMLElementID.info {
                segment.info = try parseInfo(data: data, header: child)
            } else if child.id == EBMLElementID.tracks {
                segment.tracks = try trackParser.parseTracks(data: Data(data[child.payloadOffset..<childEnd]))
            } else if child.id == EBMLElementID.cues {
                segment.cues = try cueParser.parseCues(data: Data(data[child.payloadOffset..<childEnd]))
            } else if child.id == EBMLElementID.cluster {
                if segment.firstClusterOffset == nil {
                    segment.firstClusterOffset = offset
                }
                segment.clusterRanges.append(
                    MatroskaClusterRange(offset: offset, payloadOffset: child.payloadOffset, endOffset: childEnd)
                )
                segment.packets += try clusterParser.parseCluster(
                    data: data,
                    header: child,
                    timecodeScale: segment.info.timecodeScale,
                    trackDefaultDurations: MatroskaTrackTiming.defaultDurations(for: segment.tracks)
                )
            }
            offset = childEnd
            segment.parsedUntilOffset = offset
        }
        applyTrackDurations(to: &segment)
        return segment
    }

    private func applyTrackDurations(to segment: inout MatroskaSegment) {
        let durations = MatroskaTrackTiming.defaultDurations(for: segment.tracks)
        guard !durations.isEmpty else { return }
        segment.packets = segment.packets.map { packet in
            var adjusted = packet
            if adjusted.timestamp.duration == nil {
                adjusted.timestamp.duration = durations[packet.trackID]
            }
            return adjusted
        }
    }

    private func parseInfo(data: Data, header: EBMLElementHeader) throws -> MatroskaInfo {
        var info = MatroskaInfo()
        var offset = header.payloadOffset
        let end = payloadEnd(header)
        while offset < end {
            let child = try reader.readHeader(data: data, offset: offset)
            let childEnd = payloadEnd(child)
            if child.id == EBMLElementID.timecodeScale {
                info.timecodeScale = Int64(try reader.readUInt(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0)))
            } else if child.id == EBMLElementID.duration {
                info.duration = try reader.readFloat(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0))
            }
            offset = childEnd
        }
        return info
    }

    private func payloadEnd(_ header: EBMLElementHeader) -> Int {
        header.payloadOffset + Int(header.size ?? 0)
    }

    private func payloadEnd(_ header: EBMLElementHeader, defaultEnd: Int) -> Int {
        header.size.map { header.payloadOffset + Int($0) } ?? defaultEnd
    }
}

import CoreMedia
import Foundation

public struct MatroskaSegmentParser: Sendable {
    private let reader = EBMLReader()
    private let trackParser = MatroskaTrackParser()
    private let seekHeadParser = MatroskaSeekHeadParser()
    private let cueParser = MatroskaCueParser()
    private let clusterParser = MatroskaClusterParser()

    public init() {}

    public func parse(data: Data) throws -> MatroskaSegment {
        var offset = 0
        let ebml = try reader.readHeader(data: data, offset: offset)
        guard ebml.id == EBMLElementID.ebml else { throw EBMLError.invalidMatroska("missing EBML header") }
        offset = try reader.payloadRange(
            for: ebml,
            elementOffset: offset,
            parentEnd: data.count,
            dataCount: data.count
        ).upperBound
        let segmentHeader = try reader.readHeader(data: data, offset: offset)
        guard segmentHeader.id == EBMLElementID.segment else { throw EBMLError.invalidMatroska("missing Segment") }
        return try parseSegmentBody(data: data, segmentHeader: segmentHeader, elementOffset: offset)
    }

    private func parseSegmentBody(
        data: Data,
        segmentHeader: EBMLElementHeader,
        elementOffset: Int
    ) throws -> MatroskaSegment {
        var segment = MatroskaSegment()
        segment.segmentPayloadOffset = segmentHeader.payloadOffset
        let logicalRange: Range<Int>
        let logicalDataEnd: Int
        if segmentHeader.size == nil {
            logicalRange = try reader.payloadRange(
                for: segmentHeader,
                elementOffset: elementOffset,
                parentEnd: data.count,
                dataCount: data.count,
                unknownSizeEnd: data.count
            )
            logicalDataEnd = data.count
            segment.segmentEndOffset = nil
        } else {
            logicalRange = try reader.payloadRange(
                for: segmentHeader,
                elementOffset: elementOffset,
                parentEnd: Int.max,
                dataCount: Int.max
            )
            logicalDataEnd = Int.max
            segment.segmentEndOffset = logicalRange.upperBound
        }
        let availableEnd = min(data.count, logicalRange.upperBound)
        var offset = logicalRange.lowerBound
        segment.parsedUntilOffset = offset
        while offset < availableEnd {
            let child = try reader.readHeader(data: data, offset: offset)
            let declaredChildRange = try reader.payloadRange(
                for: child,
                elementOffset: offset,
                parentEnd: logicalRange.upperBound,
                dataCount: logicalDataEnd
            )
            guard declaredChildRange.upperBound <= data.count else {
                if child.id == EBMLElementID.cluster {
                    if segment.firstClusterOffset == nil {
                        segment.firstClusterOffset = offset
                    }
                    segment.clusterRanges.append(
                        MatroskaClusterRange(
                            offset: offset,
                            payloadOffset: child.payloadOffset,
                            endOffset: declaredChildRange.upperBound
                        )
                    )
                }
                segment.parsedUntilOffset = offset
                break
            }
            let childRange = try reader.payloadRange(
                for: child,
                elementOffset: offset,
                parentEnd: logicalRange.upperBound,
                dataCount: data.count
            )
            if child.id == EBMLElementID.seekHead {
                segment.seekHead = try seekHeadParser.parse(data: Data(data[childRange]))
            } else if child.id == EBMLElementID.info {
                segment.info = try parseInfo(data: data, payloadRange: childRange)
            } else if child.id == EBMLElementID.tracks {
                segment.tracks = try trackParser.parseTracks(data: Data(data[childRange]))
            } else if child.id == EBMLElementID.cues {
                segment.cues = try cueParser.parseCues(data: Data(data[childRange]))
            } else if child.id == EBMLElementID.cluster {
                if segment.firstClusterOffset == nil {
                    segment.firstClusterOffset = offset
                }
                segment.clusterRanges.append(
                    MatroskaClusterRange(
                        offset: offset,
                        payloadOffset: child.payloadOffset,
                        endOffset: childRange.upperBound
                    )
                )
                segment.packets += try clusterParser.parseCluster(
                    data: data,
                    header: child,
                    elementOffset: offset,
                    timecodeScale: segment.info.timecodeScale,
                    trackDefaultDurations: MatroskaTrackTiming.defaultDurations(for: segment.tracks)
                )
            }
            offset = childRange.upperBound
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

    private func parseInfo(data: Data, payloadRange: Range<Int>) throws -> MatroskaInfo {
        var info = MatroskaInfo()
        var offset = payloadRange.lowerBound
        while offset < payloadRange.upperBound {
            let child = try reader.readHeader(data: data, offset: offset)
            let childRange = try reader.payloadRange(
                for: child,
                elementOffset: offset,
                parentEnd: payloadRange.upperBound,
                dataCount: data.count
            )
            if child.id == EBMLElementID.timecodeScale {
                let scale = try reader.exactInt64(reader.readUInt(
                    data: data,
                    offset: childRange.lowerBound,
                    size: childRange.count
                ))
                guard scale > 0 else {
                    throw EBMLError.invalidMatroska("TimecodeScale must be positive")
                }
                info.timecodeScale = scale
            } else if child.id == EBMLElementID.duration {
                info.duration = try reader.readFloat(
                    data: data,
                    offset: childRange.lowerBound,
                    size: childRange.count
                )
            }
            offset = childRange.upperBound
        }
        return info
    }
}

import CoreMedia
import Foundation

struct PESPacketParser: Sendable {
    func parse(_ data: Data, stream: MPEGTSStream) throws -> MediaPacket? {
        try parsePackets(data, stream: stream).first
    }

    func parsePackets(_ data: Data, stream: MPEGTSStream) throws -> [MediaPacket] {
        let pes = try parsePES(data)
        switch stream.codec {
        case "aac":
            return splitAACPackets(pes: pes, stream: stream)
        case "ac3", "eac3":
            return makeDolbyPacket(pes: pes, stream: stream).map { [$0] } ?? []
        default:
            return makePacket(
                payload: pes.payload,
                stream: stream,
                pts: pes.pts,
                dts: pes.dts,
                duration: nil
            ).map { [$0] } ?? []
        }
    }

    private func parsePES(_ data: Data) throws -> PESPayload {
        guard data.count >= 9 else {
            throw MPEGTransportStreamError.malformedPES("packet shorter than PES header")
        }
        guard data[0] == 0x00, data[1] == 0x00, data[2] == 0x01 else {
            throw MPEGTransportStreamError.malformedPES("missing packet start code")
        }
        let flags = data[7]
        let headerLength = Int(data[8])
        let payloadStart = 9 + headerLength
        guard payloadStart <= data.count else {
            throw MPEGTransportStreamError.malformedPES("header extends past PES payload")
        }
        let pts = (flags & 0x80) != 0 && data.count >= 14 ? decodeTimestamp(data, offset: 9) : nil
        let dts = (flags & 0x40) != 0 && data.count >= 19 ? decodeTimestamp(data, offset: 14) : nil
        return PESPayload(
            payload: Data(data[payloadStart..<data.endIndex]),
            pts: pts,
            dts: dts
        )
    }

    private func splitAACPackets(pes: PESPayload, stream: MPEGTSStream) -> [MediaPacket] {
        var output: [MediaPacket] = []
        var cursor = 0
        var frameIndex: Int64 = 0
        while cursor < pes.payload.count {
            let remaining = Data(pes.payload[cursor..<pes.payload.endIndex])
            guard let header = AACADTSHeader.parse(remaining) else { break }
            guard cursor + header.frameLength <= pes.payload.count else { break }
            let dataStart = cursor + header.headerLength
            let dataEnd = cursor + header.frameLength
            let duration = audioDuration(sampleCount: 1_024, sampleRate: header.sampleRate)
            if let packet = makePacket(
                payload: Data(pes.payload[dataStart..<dataEnd]),
                stream: stream,
                pts: shifted(timestamp90k: pes.pts, duration: duration, frameIndex: frameIndex),
                dts: shifted(timestamp90k: pes.dts, duration: duration, frameIndex: frameIndex),
                duration: duration
            ) {
                output.append(packet)
            }
            cursor += header.frameLength
            frameIndex += 1
        }
        return output
    }

    private func makeDolbyPacket(pes: PESPayload, stream: MPEGTSStream) -> MediaPacket? {
        let frame = DolbyAudioHeaderParser.parse(pes.payload, codec: stream.codec)
        let duration = frame.map { audioDuration(sampleCount: $0.sampleCount, sampleRate: $0.sampleRate) }
        return makePacket(payload: pes.payload, stream: stream, pts: pes.pts, dts: pes.dts, duration: duration)
    }

    private func makePacket(
        payload: Data,
        stream: MPEGTSStream,
        pts: Int64?,
        dts: Int64?,
        duration: CMTime?
    ) -> MediaPacket? {
        guard !payload.isEmpty else { return nil }
        return MediaPacket(
            trackID: stream.trackID,
            timestamp: PacketTimestamp(
                pts: pts.map { CMTime(value: $0, timescale: 90_000) } ?? .zero,
                dts: dts.map { CMTime(value: $0, timescale: 90_000) },
                duration: duration
            ),
            isKeyframe: isKeyframe(payload, codec: stream.codec),
            data: payload
        )
    }

    private func decodeTimestamp(_ data: Data, offset: Int) -> Int64 {
        let b0 = Int64(data[offset])
        let b1 = Int64(data[offset + 1])
        let b2 = Int64(data[offset + 2])
        let b3 = Int64(data[offset + 3])
        let b4 = Int64(data[offset + 4])
        return ((b0 & 0x0E) << 29)
            | (b1 << 22)
            | ((b2 & 0xFE) << 14)
            | (b3 << 7)
            | ((b4 & 0xFE) >> 1)
    }

    private func isKeyframe(_ payload: Data, codec: String) -> Bool {
        switch codec {
        case "h264":
            return AnnexBNALUnitParser.isH264Keyframe(payload)
        case "hevc":
            return AnnexBNALUnitParser.units(in: payload).contains { $0.hevcType == 19 || $0.hevcType == 20 }
        default:
            return true
        }
    }

    private func shifted(timestamp90k: Int64?, duration: CMTime, frameIndex: Int64) -> Int64? {
        guard let timestamp90k else { return nil }
        let offset = CMTimeMultiply(duration, multiplier: Int32(frameIndex))
        return timestamp90k + Int64(CMTimeConvertScale(offset, timescale: 90_000, method: .roundHalfAwayFromZero).value)
    }

    private func audioDuration(sampleCount: Int, sampleRate: Double) -> CMTime {
        CMTime(value: Int64(sampleCount), timescale: CMTimeScale(sampleRate.rounded()))
    }
}

private struct PESPayload {
    var payload: Data
    var pts: Int64?
    var dts: Int64?
}

import Foundation

struct MPEGTSSectionParser: Sendable {
    func parsePAT(_ payload: Data) -> Int? {
        guard let section = sectionData(from: payload), section.count >= 12, section[0] == 0x00 else { return nil }
        let sectionEnd = min(section.count, 3 + sectionLength(section))
        var offset = 8
        while offset + 4 <= sectionEnd - 4 {
            let program = readUInt16(section, offset)
            let pid = ((Int(section[offset + 2] & 0x1F)) << 8) | Int(section[offset + 3])
            if program != 0 { return pid }
            offset += 4
        }
        return nil
    }

    func parsePMT(_ payload: Data) -> [MPEGTSStream] {
        guard let section = sectionData(from: payload), section.count >= 16, section[0] == 0x02 else { return [] }
        let sectionEnd = min(section.count, 3 + sectionLength(section))
        let programInfoLength = ((Int(section[10] & 0x0F)) << 8) | Int(section[11])
        var offset = 12 + programInfoLength
        var streams: [MPEGTSStream] = []
        var trackID = 1

        while offset + 5 <= sectionEnd - 4 {
            let streamType = section[offset]
            let pid = ((Int(section[offset + 1] & 0x1F)) << 8) | Int(section[offset + 2])
            let esInfoLength = ((Int(section[offset + 3] & 0x0F)) << 8) | Int(section[offset + 4])
            let mapping = streamMapping(streamType)
            streams.append(MPEGTSStream(
                pid: pid,
                trackID: trackID,
                streamType: streamType,
                kind: mapping.kind,
                codec: mapping.codec
            ))
            trackID += 1
            offset += 5 + esInfoLength
        }
        return streams.filter { $0.kind != .unknown }
    }

    private func sectionData(from payload: Data) -> Data? {
        guard let pointer = payload.first else { return nil }
        let start = Int(pointer) + 1
        guard start < payload.count else { return nil }
        return Data(payload[start..<payload.endIndex])
    }

    private func sectionLength(_ section: Data) -> Int {
        guard section.count >= 3 else { return 0 }
        return ((Int(section[1] & 0x0F)) << 8) | Int(section[2])
    }

    private func readUInt16(_ data: Data, _ offset: Int) -> Int {
        (Int(data[offset]) << 8) | Int(data[offset + 1])
    }

    private func streamMapping(_ streamType: UInt8) -> (kind: MPEGTSStreamKind, codec: String) {
        switch streamType {
        case 0x1B: return (.video, "h264")
        case 0x24: return (.video, "hevc")
        case 0x0F: return (.audio, "aac")
        case 0x03, 0x04: return (.audio, "mp3")
        case 0x81: return (.audio, "ac3")
        case 0x87: return (.audio, "eac3")
        default: return (.unknown, "streamType_0x\(String(format: "%02X", streamType))")
        }
    }
}

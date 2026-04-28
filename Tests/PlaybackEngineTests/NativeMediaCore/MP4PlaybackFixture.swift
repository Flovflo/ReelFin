import AudioToolbox
import AVFoundation
import CoreMedia
import CoreVideo
import XCTest

enum MP4PlaybackFixture {
    static func makeTinyH264AACMP4(at url: URL) async throws {
        try await makeH264AACMP4(at: url, videoFrameCount: 4, audioFrameCount: 4_096)
    }

    static func makeH264AACMP4(
        at url: URL,
        videoFrameCount: Int,
        audioFrameCount: Int
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 32,
            AVVideoHeightKey: 32
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 32,
                kCVPixelBufferHeightKey as String: 32
            ]
        )
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ])
        XCTAssertTrue(writer.canAdd(videoInput))
        XCTAssertTrue(writer.canAdd(audioInput))
        writer.add(videoInput)
        writer.add(audioInput)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let audioDurationSeconds = max(0.001, Double(audioFrameCount) / 44_100)
        for frame in 0..<videoFrameCount {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let buffer = try makePixelBuffer(gray: UInt8((frame * 40) % 255))
            let frameSeconds = videoFrameCount > 1
                ? audioDurationSeconds * Double(frame) / Double(videoFrameCount - 1)
                : 0
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(seconds: frameSeconds, preferredTimescale: 600)))
        }
        videoInput.markAsFinished()

        while !audioInput.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(audioInput.append(try makeSilentPCMSampleBuffer(frameCount: audioFrameCount)))
        audioInput.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    private static func makePixelBuffer(gray: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw CocoaError(.coderInvalidValue) }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), Int32(gray), CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private static func makeSilentPCMSampleBuffer(frameCount: Int) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )
        guard formatStatus == noErr, let format else { throw CocoaError(.coderInvalidValue) }

        let byteCount = frameCount * Int(asbd.mBytesPerFrame)
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { throw CocoaError(.coderInvalidValue) }
        let silence = [UInt8](repeating: 0, count: byteCount)
        let replaceStatus = silence.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard replaceStatus == kCMBlockBufferNoErr else { throw CocoaError(.coderInvalidValue) }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 44_100),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else { throw CocoaError(.coderInvalidValue) }
        return sampleBuffer
    }
}

import AVFoundation
import CoreVideo
import NativeMediaCore
import XCTest

final class MP4SampleBufferReaderTests: XCTestCase {
    func testExtractsCompressedVideoSamplesFromMP4() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try await makeTinyH264MP4(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let tracks = try await MP4SampleBufferReader(url: url).inspectFirstSamples(maxSamplesPerTrack: 2)
        let video = try XCTUnwrap(tracks.first { $0.kind == .video })

        XCTAssertEqual(video.codec, "avc1")
        XCTAssertGreaterThan(video.sampleCount, 0)
        XCTAssertEqual(video.firstPresentationTime?.seconds ?? -1, 0, accuracy: 0.01)
    }

    func testExtractsSamplesFromExtensionlessOriginalStreamURL() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let tracks = try await MP4SampleBufferReader(url: url, format: .mp4).inspectFirstSamples(maxSamplesPerTrack: 2)

        XCTAssertGreaterThan(tracks.first { $0.kind == .video }?.sampleCount ?? 0, 0)
        XCTAssertGreaterThan(tracks.first { $0.kind == .audio }?.sampleCount ?? 0, 0)
    }

    private func makeTinyH264MP4(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 16,
                AVVideoHeightKey: 16
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 16,
                kCVPixelBufferHeightKey as String: 16
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let buffer = try makeBlackPixelBuffer()
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(adaptor.append(buffer, withPresentationTime: .zero))
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status != .completed {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    private func makeBlackPixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            16,
            16,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw CocoaError(.coderInvalidValue)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

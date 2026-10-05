import XCTest
import AVFoundation
@testable import SenseVoiceCore

final class CoreTests: XCTestCase {
    func testChunksCoverAudioOnceAndPreferQuietBoundary() {
        var samples = [Float](repeating: 0.1, count: 65 * 16_000)
        for index in (18 * 16_000)..<(19 * 16_000) { samples[index] = 0 }
        let ranges = AudioChunks.ranges(for: samples)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, samples.count)
        XCTAssertTrue((18 * 16_000..<19 * 16_000).contains(ranges[0].upperBound))
        for (a, b) in zip(ranges, ranges.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound) }
        XCTAssertTrue(ranges.allSatisfy { !$0.isEmpty && $0.count <= 20 * 16_000 })
    }
    func testResamplesStereo48kToMono16k() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for channel in 0..<2 { for i in 0..<48_000 { buffer.floatChannelData![channel][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.1 } }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let result = try AudioReader.samples(from: url)
        XCTAssertEqual(result.count, 16_000, accuracy: 2)
        XCTAssertGreaterThan(result.map { abs($0) }.max()!, 0.05)
    }
    func testLongRecordingStreamsBoundedChunksWithoutLosingSamples() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for channel in 0..<2 {
            for i in 0..<48_000 { buffer.floatChannelData![channel][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.1 }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            for _ in 0..<131 { try file.write(from: buffer) }
        }
        var total = 0; var chunks = 0; var previousProgress = 0.0; var peak: Float = 0
        let duration = try AudioReader.forEachChunk(from: url) { samples, progress in
            XCTAssertFalse(samples.isEmpty)
            XCTAssertLessThanOrEqual(samples.count, 20 * 16_000)
            XCTAssertGreaterThanOrEqual(progress, previousProgress)
            XCTAssertLessThanOrEqual(progress, 1)
            previousProgress = progress
            total += samples.count; chunks += 1
            peak = max(peak, samples.map { abs($0) }.max() ?? 0)
        }
        XCTAssertEqual(total, 131 * 16_000, accuracy: 2)
        XCTAssertEqual(duration, 131, accuracy: 0.001)
        XCTAssertGreaterThan(chunks, 6)
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertEqual(previousProgress, 1, accuracy: 0.0001)
    }
    func testMissingModelIsNotReady() { XCTAssertFalse(ModelStore.isReady(at: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))) }
}

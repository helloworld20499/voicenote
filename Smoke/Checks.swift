import Foundation
import AVFoundation
import SenseVoiceCore

func runChecks() throws {
    func require(_ value: Bool, _ message: String) throws {
        if !value { throw PrototypeError.message("CHECK FAILED: \(message)") }
    }
    var samples = [Float](repeating: 0.1, count: 65 * 16_000)
    for index in (18 * 16_000)..<(19 * 16_000) { samples[index] = 0 }
    let ranges = AudioChunks.ranges(for: samples)
    try require(ranges.first?.lowerBound == 0 && ranges.last?.upperBound == samples.count, "full coverage")
    try require((18 * 16_000..<19 * 16_000).contains(ranges[0].upperBound), "quiet boundary")
    try require(zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound }, "no gaps or repeats")
    try require(ranges.allSatisfy { !$0.isEmpty && $0.count <= 20 * 16_000 }, "bounded segments")
    try require(AudioChunks.ranges(for: []).isEmpty, "empty audio")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
    buffer.frameLength = 48_000
    for channel in 0..<2 { for i in 0..<48_000 { buffer.floatChannelData![channel][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000)) * 0.1 } }
    do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
    let result = try AudioReader.samples(from: url)
    try require(abs(result.count - 16_000) <= 2, "48k stereo -> 16k mono duration")
    try require((result.map { abs($0) }.max() ?? 0) > 0.05, "audio remains audible")
    try require(!ModelStore.isReady(at: url), "missing installation rejected")
    print("PASS: chunk coverage, quiet boundaries, bounded segments, empty input, 48k stereo resampling, missing model.")
}

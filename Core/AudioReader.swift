import AVFoundation

public enum AudioReader {
    public static let maximumDuration: Double = 120
    public static func samples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw PrototypeError.message("录音为空，请重新录制。") }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration <= maximumDuration + 1 else { throw PrototypeError.message("原型支持最长 2 分钟的录音。") }
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(duration * 16_000)) + 1024) else {
            throw PrototypeError.message("无法转换录音格式。")
        }
        try file.read(into: input)
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if let error { throw error }
        guard status != .error, let data = output.floatChannelData, output.frameLength > 0 else {
            throw PrototypeError.message("录音格式转换失败。")
        }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}

public enum AudioChunks {
    // Prefer quiet 100 ms windows near a boundary. This is basic segmentation, not neural VAD.
    public static func ranges(for samples: [Float], sampleRate: Int = 16_000) -> [Range<Int>] {
        guard !samples.isEmpty else { return [] }
        var result: [Range<Int>] = []; var start = 0
        let maximum = 20 * sampleRate; let window = max(1, sampleRate / 10)
        while start < samples.count {
            var end = min(start + maximum, samples.count)
            if end < samples.count {
                let searchStart = start + 15 * sampleRate
                var lowest = Float.greatestFiniteMagnitude
                for candidate in stride(from: searchStart, through: end - window, by: window) {
                    let energy = samples[candidate..<(candidate + window)].reduce(Float(0)) { $0 + $1 * $1 }
                    if energy < lowest { lowest = energy; end = candidate + window / 2 }
                }
            }
            result.append(start..<end); start = end
        }
        return result
    }
}

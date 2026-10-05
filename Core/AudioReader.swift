import AVFoundation

public enum AudioReader {
    // Compatibility helper for short CLI checks; the transcription engine streams chunks.
    public static func samples(from url: URL) throws -> [Float] {
        var result: [Float] = []
        try forEachChunk(from: url) { chunk, _ in result.append(contentsOf: chunk) }
        return result
    }
    @discardableResult
    public static func forEachChunk(from url: URL, consume: ([Float], Double) throws -> Void) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { throw PrototypeError.message("录音为空，请重新录制。") }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000) else {
            throw PrototypeError.message("无法转换录音格式。")
        }
        var pending: [Float] = []; var processed = 0; var readError: Error?
        func deliver(_ count: Int) throws {
            let chunk = Array(pending.prefix(count))
            processed += count
            try consume(chunk, min(1, Double(processed) / 16_000 / duration))
            pending.removeFirst(count)
        }
        while true {
            var error: NSError?
            output.frameLength = 0
            let status = converter.convert(to: output, error: &error) { _, state in
                guard file.framePosition < file.length else { state.pointee = .endOfStream; return nil }
                do {
                    try file.read(into: input, frameCount: AVAudioFrameCount(min(4096, file.length - file.framePosition)))
                    state.pointee = .haveData; return input
                } catch { readError = error; state.pointee = .endOfStream; return nil }
            }
            if let readError { throw readError }
            if let error { throw error }
            guard status != .error else { throw PrototypeError.message("录音格式转换失败。") }
            if let data = output.floatChannelData, output.frameLength > 0 {
                pending.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
            }
            while pending.count > 20 * 16_000 {
                let range = AudioChunks.ranges(for: pending)[0]
                try deliver(range.count)
            }
            if status == .endOfStream { break }
        }
        if !pending.isEmpty { try deliver(pending.count) }
        guard processed > 0 else { throw PrototypeError.message("录音格式转换失败。") }
        return Double(processed) / 16_000
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

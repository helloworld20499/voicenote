import Foundation
import SherpaOnnxC

public struct Transcription: Sendable {
    public let text: String
    public let audioDuration: Double
    public let processingDuration: Double
}

public actor SenseVoiceEngine {
    private var recognizer: OpaquePointer?
    public init() {}
    deinit { if let recognizer { SherpaOnnxDestroyOfflineRecognizer(recognizer) } }
    public func transcribe(_ url: URL, modelDirectory: URL = ModelStore.directory,
                           progress: @escaping @Sendable (Double) -> Void = { _ in }) throws -> Transcription {
        let started = Date()
        guard ModelStore.isReady(at: modelDirectory) else { throw PrototypeError.message("请先下载 SenseVoice 模型。") }
        if recognizer == nil { try load(at: modelDirectory) }
        guard let recognizer else { throw PrototypeError.message("识别引擎未就绪。") }
        var texts: [String] = []
        let duration = try AudioReader.forEachChunk(from: url) { segment, fraction in
            guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
                throw PrototypeError.message("无法创建识别任务。")
            }
            defer { SherpaOnnxDestroyOfflineStream(stream) }
            segment.withUnsafeBufferPointer { buffer in
                SherpaOnnxAcceptWaveformOffline(stream, 16_000, buffer.baseAddress, Int32(buffer.count))
            }
            SherpaOnnxDecodeOfflineStream(recognizer, stream)
            guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { throw PrototypeError.message("无法读取识别结果。") }
            let text = result.pointee.text.map { String(cString: $0) } ?? ""
            SherpaOnnxDestroyOfflineRecognizerResult(result)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.append(text) }
            progress(fraction)
        }
        return Transcription(text: texts.joined(separator: "\n"), audioDuration: duration,
                             processingDuration: Date().timeIntervalSince(started))
    }
    private func load(at root: URL) throws {
        let model = root.appendingPathComponent("model.int8.onnx").path
        let tokens = root.appendingPathComponent("tokens.txt").path
        // Keep all C strings alive until the C API has copied the configuration.
        recognizer = model.withCString { modelPointer in
            tokens.withCString { tokensPointer in
                "auto".withCString { language in
                    "cpu".withCString { provider in
                        "greedy_search".withCString { decoding in
                            var config = SherpaOnnxOfflineRecognizerConfig()
                            config.feat_config.sample_rate = 16_000; config.feat_config.feature_dim = 80
                            config.model_config.sense_voice.model = modelPointer
                            config.model_config.sense_voice.language = language
                            config.model_config.sense_voice.use_itn = 1
                            config.model_config.tokens = tokensPointer
                            config.model_config.num_threads = 2
                            config.model_config.provider = provider
                            config.decoding_method = decoding
                            config.max_active_paths = 4
                            return SherpaOnnxCreateOfflineRecognizer(&config)
                        }
                    }
                }
            }
        }
        guard recognizer != nil else { throw PrototypeError.message("SenseVoice 初始化失败，请检查模型文件。") }
    }
}

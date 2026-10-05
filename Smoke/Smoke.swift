import Foundation
import SenseVoiceCore

@main struct Smoke {
    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "--check" { try runChecks(); return }
        guard CommandLine.arguments.count >= 3 else {
            print("Usage: sensevoice-smoke MODEL_DIRECTORY AUDIO.wav [MORE.wav ...]"); return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try await ModelStore.install(at: root) { _ in }
        let engine = SenseVoiceEngine()
        for path in CommandLine.arguments.dropFirst(2) {
            let result = try await engine.transcribe(URL(fileURLWithPath: path), modelDirectory: root)
            print("\(path): \(result.text)")
            print(String(format: "audio=%.2fs processing=%.2fs", result.audioDuration, result.processingDuration))
            guard !result.text.isEmpty else { throw PrototypeError.message("Empty transcription") }
        }
    }
}

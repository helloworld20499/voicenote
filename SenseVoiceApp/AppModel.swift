import SwiftUI
import AVFoundation
import SenseVoiceCore

@MainActor final class AppModel: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var lastSavedID: UUID?
    private var libraryReady = false
    @Published var recordings: [Recording] = []
    @Published var modelReady = ModelStore.isReady()
    @Published var downloading = false
    @Published var downloadProgress: Double = 0
    @Published var isRecording = false
    @Published var requestingPermission = false
    @Published var elapsed: Double = 0
    @Published var transcribingID: UUID?
    @Published var transcriptionProgress: Double = 0
    @Published var playingID: UUID?
    @Published var error: String?
    @Published var notice: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var pendingID: UUID?
    private var pendingURL: URL?
    private let engine = SenseVoiceEngine()
    private var interruptionObserver: NSObjectProtocol?
    var busy: Bool { downloading || transcribingID != nil || isRecording || requestingPermission }
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
    }
    var indexURL: URL { Self.root.appendingPathComponent("recordings.json") }
    override init() {
        super.init()
        do {
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            var root = Self.root; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try root.setResourceValues(values)
            let loaded = try RecordingStore(directory: Self.root).load()
            recordings = loaded.records; libraryReady = true
            if loaded.recoveredCount > 0 { notice = "已找回 \(loaded.recoveredCount) 条本机录音，可稍后转录。" }
        } catch { self.error = "无法读取录音列表：\(error.localizedDescription)" }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.stopRecording(transcribe: false); self?.stopPlayback(); self?.notice = "音频被系统中断，录音已停止。已保存的录音可稍后转录。" }
            }
        }
    }
    func downloadModel() {
        guard !busy else { return }
        downloading = true; downloadProgress = 0
        Task {
            defer { downloading = false }
            do {
                try await ModelStore.install { [weak self] value in
                    Task { @MainActor in self?.downloadProgress = value }
                }
                modelReady = ModelStore.isReady()
                notice = "模型已就绪，可以离线录音和转录。"
            } catch { self.error = error.localizedDescription }
        }
    }
    func startRecording() {
        guard !busy else { return }
        guard libraryReady else { error = "录音列表无法读取，请先检查本机 Recordings/recordings.json，避免覆盖原有文字。"; return }
        stopPlayback(); requestingPermission = true
        Task {
            defer { requestingPermission = false }
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard granted else { error = "请在 设置 → 隐私与安全性 → 麦克风 中允许本 App 录音。"; return }
            // Permission UI may have left the app inactive. Start only while foregrounded.
            guard UIApplication.shared.applicationState == .active else { notice = "回到 App 后点击开始录音。"; return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .default)
                try session.setActive(true)
                let id = UUID()
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let url = Self.root.appendingPathComponent("录音_\(formatter.string(from: Date()))_\(id.uuidString.prefix(8)).wav")
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
                let recording = try AVAudioRecorder(url: url, settings: settings)
                recording.delegate = self; recording.isMeteringEnabled = true
                guard recording.record() else { throw PrototypeError.message("无法启动麦克风录音。") }
                try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
                recorder = recording; pendingID = id; pendingURL = url
                elapsed = 0; isRecording = true; notice = nil
                UIApplication.shared.isIdleTimerDisabled = false
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.isRecording else { return }
                        self.elapsed = self.recorder?.currentTime ?? self.elapsed
                    }
                }
            } catch {
                self.error = error.localizedDescription
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
    func stopRecording(transcribe: Bool = false) {
        guard isRecording, let id = pendingID, let url = pendingURL else { return }
        let duration = max(recorder?.currentTime ?? 0, elapsed)
        isRecording = false; timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil; pendingID = nil; pendingURL = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard duration > 0.2 else { try? FileManager.default.removeItem(at: url); notice = "录音太短，请再说几句。"; return }
        recordings.insert(Recording(id: id, createdAt: Date().addingTimeInterval(-duration), filename: url.lastPathComponent, duration: duration, text: ""), at: 0)
        guard persist() else { return }
        lastSavedID = id
        notice = "录音已保存到「资料库」，可随时播放或转录。"
        if transcribe { transcribeRecording(id) }
    }
    func transcribeRecording(_ id: UUID) {
        guard !busy, modelReady, let record = recordings.first(where: { $0.id == id }) else { return }
        stopPlayback(); transcribingID = id; transcriptionProgress = 0; notice = nil
        Task {
            defer { transcribingID = nil }
            do {
                let result = try await engine.transcribe(Self.root.appendingPathComponent(record.filename)) { [weak self] value in
                    Task { @MainActor in self?.transcriptionProgress = value }
                }
                if let index = recordings.firstIndex(where: { $0.id == id }) {
                    let previous = recordings
                    recordings[index].text = result.text
                    recordings[index].duration = result.audioDuration
                    recordings[index].processingDuration = result.processingDuration
                    guard persist() else { recordings = previous; return }
                    notice = result.text.isEmpty ? "没有识别到文字，录音已保留。" : "转录完成，录音和文字已保存在本机。"
                }
            } catch { self.error = "转录失败，录音已保留：\(error.localizedDescription)" }
        }
    }
    func updateText(_ id: UUID, text: String) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        let previous = recordings
        recordings[index].text = text
        if !persist() { recordings = previous }
    }
    func togglePlayback(_ record: Recording) {
        if playingID == record.id { stopPlayback(); return }
        guard !busy else { return }
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: Self.root.appendingPathComponent(record.filename))
            player.delegate = self
            guard player.play() else { throw PrototypeError.message("录音无法播放。") }
            self.player = player; playingID = record.id
        } catch { self.error = error.localizedDescription; stopPlayback() }
    }
    func stopPlayback() {
        player?.stop(); player = nil; playingID = nil
        if !isRecording { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    func delete(_ record: Recording) {
        guard !busy else { return }
        if playingID == record.id { stopPlayback() }
        do {
            let audio = Self.root.appendingPathComponent(record.filename)
            if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) }
            recordings.removeAll { $0.id == record.id }; persist()
        } catch { self.error = "删除失败：\(error.localizedDescription)" }
    }
    func wentToBackground() {
        // An active recording owns the background audio session; do not deactivate it.
        if isRecording { return }
        stopPlayback()
    }
    @discardableResult private func persist() -> Bool {
        do {
            guard libraryReady else { throw PrototypeError.message("原有录音列表无法读取，已停止写入以保护内容。") }
            try RecordingStore(directory: Self.root).save(recordings)
            return true
        } catch { self.error = "保存失败：\(error.localizedDescription)"; return false }
    }
    func deleteTranscript(_ id: UUID) {
        guard !busy, libraryReady else { return }
        do {
            recordings = try RecordingStore(directory: Self.root).removingTranscript(id, from: recordings)
            notice = "转录文字已删除，录音保留，可以重新转录。"
        } catch { self.error = "删除文字失败：\(error.localizedDescription)" }
    }
    func reloadRecordings() {
        guard !busy else { return }
        do {
            let result = try RecordingStore(directory: Self.root).load()
            recordings = result.records; libraryReady = true
        } catch { self.error = "无法读取录音列表：\(error.localizedDescription)" }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.stopRecording(transcribe: false)
            self.error = "录音写入被中断，请检查已保存的音频和可用空间。"
        }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            if !flag { self.error = "录音被打断，已保留可用音频。" }
            self.stopRecording(transcribe: false)
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stopPlayback() }
    }
}

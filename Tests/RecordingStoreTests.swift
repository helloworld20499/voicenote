import XCTest
import AVFoundation
@testable import SenseVoiceCore

final class RecordingStoreTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func writeAudio(_ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for index in 0..<16_000 { buffer.floatChannelData![0][index] = 0.01 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
    func testRecoversUnindexedAudioAndKeepsSavedTextAcrossReloads() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(directory: root)
        let saved = Recording(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), filename: "saved.wav", duration: 1, text: "保留 edited text")
        try writeAudio(root.appendingPathComponent(saved.filename))
        try store.save([saved])
        try writeAudio(root.appendingPathComponent("录音_刚保存.wav"))
        try Data().write(to: root.appendingPathComponent("empty.wav"))
        let loaded = try store.load()
        XCTAssertEqual(loaded.recoveredCount, 1)
        XCTAssertEqual(loaded.records.count, 2)
        XCTAssertEqual(loaded.records.first(where: { $0.id == saved.id })?.text, saved.text)
        XCTAssertEqual(try store.load().recoveredCount, 0)
    }
    func testDeletingTranscriptPreservesPlayableAudioAndPersists() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(directory: root)
        let record = Recording(id: UUID(), createdAt: Date(), filename: "keep.wav", duration: 1, text: "删除这段文字", processingDuration: 0.2)
        let audio = root.appendingPathComponent(record.filename)
        try writeAudio(audio)
        let before = try Data(contentsOf: audio)
        try store.save([record])
        let result = try store.removingTranscript(record.id, from: [record])
        XCTAssertEqual(result[0].text, ""); XCTAssertNil(result[0].processingDuration)
        XCTAssertEqual(try Data(contentsOf: audio), before)
        XCTAssertGreaterThan(try AVAudioFile(forReading: audio).length, 0)
        XCTAssertEqual(try store.load().records[0].text, "")
    }
    func testCorruptIndexIsNotSilentlyOverwritten() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(directory: root)
        let original = Data("damaged index with user's text".utf8)
        try original.write(to: store.indexURL)
        try writeAudio(root.appendingPathComponent("orphan.wav"))
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.indexURL), original)
    }
    func testArchiveAvoidsOverwriteAndDeletionDoesNotTouchSource() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let archive = MarkdownArchive(directory: root.appendingPathComponent("Transcripts"))
        let source = root.appendingPathComponent("source.wav")
        try writeAudio(source)
        let first = try archive.save(text: "# 中文 English 😀", filename: "声笺.md")
        let second = try archive.save(text: "# second", filename: "声笺.md")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "# 中文 English 😀")
        try archive.delete(first)
        XCTAssertEqual(try archive.files().map { $0.resolvingSymlinksInPath() }, [second.resolvingSymlinksInPath()])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertThrowsError(try archive.delete(source))
    }
}

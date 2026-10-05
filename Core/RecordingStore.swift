import Foundation
import AVFoundation

public struct RecordingLoadResult {
    public let records: [Recording]
    public let recoveredCount: Int
}

public struct RecordingStore {
    public let directory: URL
    public var indexURL: URL { directory.appendingPathComponent("recordings.json") }
    public init(directory: URL) { self.directory = directory }
    public func save(_ records: [Recording]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public func load() throws -> RecordingLoadResult {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Never replace a corrupt index silently: it may contain irreplaceable edited text.
        var records = manager.fileExists(atPath: indexURL.path)
            ? try JSONDecoder().decode([Recording].self, from: Data(contentsOf: indexURL)) : []
        let knownFiles = Set(records.map(\.filename))
        var recovered = 0
        for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) {
            guard url.pathExtension.lowercased() == "wav", !knownFiles.contains(url.lastPathComponent),
                  let audio = try? AVAudioFile(forReading: url), audio.length > 0 else { continue }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            records.append(Recording(id: UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID(),
                                     createdAt: date, filename: url.lastPathComponent,
                                     duration: Double(audio.length) / audio.processingFormat.sampleRate, text: ""))
            recovered += 1
        }
        records.sort { $0.createdAt > $1.createdAt }
        if recovered > 0 { try save(records) }
        return RecordingLoadResult(records: records, recoveredCount: recovered)
    }
    public func removingTranscript(_ id: UUID, from records: [Recording]) throws -> [Recording] {
        var updated = records
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return updated }
        updated[index].text = ""; updated[index].processingDuration = nil
        try save(updated)
        return updated
    }
}

public struct MarkdownArchive {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func files() throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    public func save(text: String, filename: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = Self.availableURL(filename: filename, in: directory)
        try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
    public static func availableURL(filename: String, in directory: URL) -> URL {
        let safe = URL(fileURLWithPath: filename).lastPathComponent
        let base = URL(fileURLWithPath: safe).deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(safe)
        var count = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)_\(count).md"); count += 1
        }
        return candidate
    }
    public func delete(_ url: URL) throws {
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == directory.resolvingSymlinksInPath(),
              url.pathExtension.lowercased() == "md" else { throw PrototypeError.message("无法删除这个文件。") }
        try FileManager.default.removeItem(at: url)
    }
}

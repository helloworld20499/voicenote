import Foundation
import CryptoKit

public enum PrototypeError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public enum ModelStore {
    public static let revision = "2365baeacb507f821a0c8120fcee3d484dba7a07"
    public static let modelSize: Int64 = 239_233_841
    public static let modelHash = "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SenseVoicePrototype/Models", isDirectory: true)
    }
    public static func isReady(at root: URL = directory) -> Bool {
        let model = root.appendingPathComponent("model.int8.onnx")
        let marker = root.appendingPathComponent("verified-\(revision)")
        let size = (try? model.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return size == Int(modelSize) && FileManager.default.fileExists(atPath: root.appendingPathComponent("tokens.txt").path)
            && FileManager.default.fileExists(atPath: marker.path)
    }
    public static func install(at root: URL = directory, progress: @escaping @Sendable (Double) -> Void) async throws {
        if isReady(at: root) { progress(1); return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (index, name) in ["model.int8.onnx", "tokens.txt"].enumerated() {
            let source = URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/\(revision)/\(name)")!
            let target = root.appendingPathComponent(name)
            let temporary = try await FileDownload.fetch(source) { fraction in
                progress(index == 0 ? fraction * 0.98 : 0.98 + fraction * 0.02)
            }
            defer { try? FileManager.default.removeItem(at: temporary) }
            if name == "model.int8.onnx" {
                let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard size == Int(modelSize), try sha256(temporary) == modelHash else {
                    throw PrototypeError.message("模型校验失败，请重新下载。")
                }
            } else {
                let data = try Data(contentsOf: temporary)
                guard data.count == 315_894, String(data: data, encoding: .utf8) != nil, try sha256(temporary) == "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc" else {
                    throw PrototypeError.message("词表校验失败，请重新下载。")
                }
            }
            // The old installation is never marked ready while being replaced.
            try? FileManager.default.removeItem(at: root.appendingPathComponent("verified-\(revision)"))
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: temporary, to: target)
            var excluded = target
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
        }
        try Data(revision.utf8).write(to: root.appendingPathComponent("verified-\(revision)"), options: .atomic)
        progress(1)
    }
    private static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var saved: URL?
    private var failure: Error?
    private init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    static func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = FileDownload(progress: progress)
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 1800
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            session.downloadTask(with: url).resume()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
                throw PrototypeError.message("下载失败，请检查网络后重试。")
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: url); saved = url
        } catch { failure = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate(); self.session = nil; continuation = nil }
        if let error = error ?? failure { continuation?.resume(throwing: error) }
        else if let saved { continuation?.resume(returning: saved) }
        else { continuation?.resume(throwing: PrototypeError.message("下载没有生成有效文件。")) }
    }
}

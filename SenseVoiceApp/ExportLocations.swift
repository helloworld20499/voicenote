import SwiftUI
import UniformTypeIdentifiers
import SenseVoiceCore

@MainActor final class ExportLocations: ObservableObject {
    @Published private(set) var iCloudFolderName: String?
    private let iCloudBookmarkKey = "iCloudMarkdownFolder"
    @Published var folderName: String?
    @Published var files: [URL] = []
    private let defaults: UserDefaults
    private let bookmarkKey = "preferredMarkdownFolder"
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Transcripts", isDirectory: true)
    }
    private var archive: MarkdownArchive { MarkdownArchive(directory: Self.directory) }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: bookmarkKey) {
            var stale = false
            folderName = (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?.lastPathComponent
        }
        if let data = defaults.data(forKey: iCloudBookmarkKey) {
            var stale = false
            iCloudFolderName = (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?.lastPathComponent
        }
        refresh()
    }
    func refresh() { files = (try? archive.files()) ?? [] }
    func saveLocally(text: String, filename: String) throws -> URL {
        let url = try archive.save(text: text, filename: filename); refresh(); return url
    }
    func delete(_ url: URL) throws { try archive.delete(url); refresh() }
    func remember(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        guard isDirectory == true else {
            throw PrototypeError.message("请选择一个文件夹。")
        }
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey); folderName = url.lastPathComponent
    }
    func forget() { defaults.removeObject(forKey: bookmarkKey); folderName = nil }
    func saveToPreferred(text: String, filename: String) throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else { throw PrototypeError.message("请先选择常用保存文件夹。") }
        return try save(text: text, filename: filename, bookmark: data, key: bookmarkKey, requireICloud: false)
    }
    func rememberICloudFolder(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try validateICloudFolder(url)
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: iCloudBookmarkKey)
        iCloudFolderName = url.lastPathComponent
    }
    func forgetICloudFolder() {
        defaults.removeObject(forKey: iCloudBookmarkKey); iCloudFolderName = nil
    }
    func saveToICloud(text: String, filename: String) throws -> URL {
        guard let data = defaults.data(forKey: iCloudBookmarkKey) else {
            throw PrototypeError.message("请先在 iCloud Drive 中选择一个文件夹。")
        }
        return try save(text: text, filename: filename, bookmark: data, key: iCloudBookmarkKey, requireICloud: true)
    }
    private func validateICloudFolder(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey])
        guard values.isDirectory == true, values.isUbiquitousItem == true else {
            throw PrototypeError.message("请选择 iCloud Drive 中的文件夹。若没有 iCloud Drive，请先在系统设置中登录 Apple Account 并开启 iCloud Drive。")
        }
    }
    private func save(text: String, filename: String, bookmark data: Data, key: String, requireICloud: Bool) throws -> URL {
        var stale = false
        let folder = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        if requireICloud { try validateICloudFolder(folder) }
        if stale { defaults.set(try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil), forKey: key) }
        let url = MarkdownArchive.availableURL(filename: filename, in: folder)
        // Cloud file providers coordinate access and own the subsequent remote sync.
        var coordinationError: NSError?; var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { destination in
            do { try Data(text.utf8).write(to: destination, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        return url
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator; picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void
        let onCancel: () -> Void
        init(onSelect: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect; self.onCancel = onCancel
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onSelect(url) }
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers
import SenseVoiceCore

struct ExportSelection: Identifiable {
    let id = UUID()
    let records: [Recording]
}

struct ExportTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "md") ?? .plainText] }
    let text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct TextExportView: View {
    let records: [Recording]
    @EnvironmentObject private var locations: ExportLocations
    @EnvironmentObject private var drive: GoogleDriveService
    @State private var folderPicker = false
    @State private var uploadedURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var document: ExportTextDocument?
    @State private var filename = "声笺.md"
    private let contentType = UTType(filenameExtension: "md") ?? .plainText
    @State private var showExporter = false
    @State private var preparing = false
    @State private var message: String?
    @State private var error: String?
    private var available: [Recording] { RecordingTextExport.exportable(records) }
    var body: some View {
        NavigationStack {
            Form {
                if let message {
                    Section("保存结果") {
                        Label(message, systemImage: "checkmark.circle").foregroundStyle(.green)
                        if let uploadedURL { Link("查看 Google Drive 文件", destination: uploadedURL) }
                    }
                }
                Section("导出内容") {
                    Label("\(available.count) 条文字记录", systemImage: "doc.text")
                    if available.count < records.count {
                        Text("\(records.count - available.count) 条暂无文字的记录将跳过。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("多条记录会按时间顺序合并为一个文件，保留日期和时间，仅包含已保存的文字。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("文件格式") {
                    Label("Markdown（.md）", systemImage: "doc.plaintext")
                    Text("按日期分组，方便 AI 阅读和整理。文件只包含文字，不包含录音。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("保存目标") {
                    Button("保存到本机", systemImage: "iphone") { prepare(.local) }
                    if let folder = locations.folderName {
                        Button("保存到常用文件夹：\(folder)", systemImage: "folder.fill") { prepare(.preferred) }
                    }
                    Button("上传到 Google Drive", systemImage: "cloud") { prepare(.google) }
                        .disabled(!drive.configured || drive.busy)
                    if !drive.configured {
                        Text("Google Drive 等待配置 OAuth Client ID。可先保存到本机。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("上传到 Google Drive / 声笺；首次上传会请你登录并授权，之后直接上传。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("另选保存位置…", systemImage: "folder") { prepare(.system) }
                    Button(locations.folderName == nil ? "设置常用文件夹…" : "更换常用文件夹…") { folderPicker = true }
                    if preparing { ProgressView("正在保存…") }
                }.disabled(available.isEmpty || preparing)
            }
            .navigationTitle("导出文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(preparing) } }
            .sheet(isPresented: $folderPicker) {
                FolderPicker(onSelect: { url in
                    do { try locations.remember(url) } catch { self.error = error.localizedDescription }
                    folderPicker = false
                }, onCancel: { folderPicker = false })
            }
            .fileExporter(isPresented: $showExporter, document: document, contentType: contentType,
                          defaultFilename: filename) { result in
                switch result {
                case .success:
                    message = "文件已导出。若保存到云盘，同步进度请在对应云盘 App 查看。"
                case .failure(let failure):
                    // User cancellation is not an export error.
                    if (failure as NSError).code != NSUserCancelledError { error = failure.localizedDescription }
                }
            }
            .alert("导出失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private enum Target { case local, preferred, google, system }
    private func prepare(_ target: Target) {
        preparing = true; message = nil; uploadedURL = nil
        let snapshot = records; let zone = TimeZone.current
        Task {
            defer { preparing = false }
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let text = try RecordingTextExport.contents(snapshot, timeZone: zone)
                    let name = try RecordingTextExport.filename(snapshot, timeZone: zone)
                    return (text, name)
                }.value
                switch target {
                case .local:
                    let url = try locations.saveLocally(text: prepared.0, filename: prepared.1)
                    message = "已保存：\(url.lastPathComponent)。在「文件与云盘」中查看、分享或删除。"
                case .preferred:
                    let url = try locations.saveToPreferred(text: prepared.0, filename: prepared.1)
                    message = "已保存到常用文件夹：\(url.lastPathComponent)。云盘同步由对应 App 完成。"
                case .google:
                    let result = try await drive.upload(text: prepared.0, filename: prepared.1)
                    uploadedURL = result.viewURL
                    message = "已上传到 Google Drive / 声笺：\(result.name ?? prepared.1)"
                case .system:
                    document = ExportTextDocument(text: prepared.0); filename = prepared.1
                    showExporter = true
                }
            } catch { if !GoogleDriveService.isCancellation(error) { self.error = error.localizedDescription } }
        }
    }
}

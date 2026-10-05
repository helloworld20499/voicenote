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
                Section {
                    Button(action: prepare) {
                        HStack {
                            Label("选择保存位置", systemImage: "folder")
                            Spacer()
                            if preparing { ProgressView() }
                        }
                    }.disabled(available.isEmpty || preparing)
                    Text("保存到「我的 iPhone」即可下载到本机。已在「文件」App 启用的 iCloud Drive、Google Drive、OneDrive 等，也可作为保存位置。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("如果云盘没有出现在位置列表，请先安装并登录对应 App，在「文件」App 的浏览页面启用它。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) } }
            }
            .navigationTitle("导出文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(preparing) } }
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
    private func prepare() {
        preparing = true; message = nil
        let snapshot = records; let zone = TimeZone.current
        Task {
            defer { preparing = false }
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let text = try RecordingTextExport.contents(snapshot, timeZone: zone)
                    let name = try RecordingTextExport.filename(snapshot, timeZone: zone)
                    return (text, name)
                }.value
                document = ExportTextDocument(text: prepared.0); filename = prepared.1
                showExporter = true
            } catch { self.error = error.localizedDescription }
        }
    }
}

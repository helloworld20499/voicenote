import SwiftUI
import SenseVoiceCore

struct ExportSelection: Identifiable {
    let id = UUID()
    let records: [Recording]
}

struct TextExportView: View {
    let records: [Recording]
    @EnvironmentObject private var locations: ExportLocations
    @Environment(\.dismiss) private var dismiss
    @State private var folderPicker = false
    @State private var pendingExport: (text: String, filename: String)?
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
                    }
                }
                Section("导出内容") {
                    Label("\(available.count) 条文字记录 · Markdown（.md）", systemImage: "doc.text")
                    if available.count < records.count {
                        Text("\(records.count - available.count) 条暂无文字的记录将跳过。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("按时间顺序合并，只包含已保存的文字。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("保存目标") {
                    Button("保存到本机", systemImage: "iphone") { prepare(.local) }
                    Button("上传到 iCloud", systemImage: "icloud") { prepare(.iCloud) }
                        .contextMenu {
                            Button("更换 iCloud 文件夹") {
                                prepare(.iCloud, chooseFolder: true)
                            }
                        }
                    Text(locations.iCloudFolderName.map { "iCloud 文件夹：\($0)。长按上传按钮可更换。" }
                         ?? "首次上传请选择 iCloud Drive 中的文件夹，之后会记住这个位置。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if preparing { ProgressView("正在保存…") }
                }.disabled(available.isEmpty || preparing)
            }
            .navigationTitle("导出文字").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(preparing) } }
            .sheet(isPresented: $folderPicker, onDismiss: { pendingExport = nil }) {
                FolderPicker(onSelect: { url in
                    do {
                        try locations.rememberICloudFolder(url)
                        if let pendingExport {
                            let saved = try locations.saveToICloud(text: pendingExport.text, filename: pendingExport.filename)
                            cloudSaved(saved)
                        }
                    } catch { self.error = error.localizedDescription }
                    pendingExport = nil; folderPicker = false
                }, onCancel: { pendingExport = nil; folderPicker = false })
            }
            .alert("导出失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private enum Target { case local, iCloud }
    private func cloudSaved(_ url: URL) {
        message = "已保存到 iCloud Drive：\(url.lastPathComponent)。上传由系统完成；离线时会等待联网同步。"
    }
    private func prepare(_ target: Target, chooseFolder: Bool = false) {
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
                switch target {
                case .local:
                    let url = try locations.saveLocally(text: prepared.0, filename: prepared.1)
                    message = "已保存：\(url.lastPathComponent)。位置：文件 App → 我的 iPhone → 声笺 → Transcripts。"
                case .iCloud:
                    if locations.iCloudFolderName != nil && !chooseFolder {
                        do { cloudSaved(try locations.saveToICloud(text: prepared.0, filename: prepared.1)) }
                        catch {
                            locations.forgetICloudFolder()
                            throw error
                        }
                    } else {
                        pendingExport = (prepared.0, prepared.1); folderPicker = true
                    }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

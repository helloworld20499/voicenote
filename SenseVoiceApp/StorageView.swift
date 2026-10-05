import SwiftUI
import GoogleSignInSwift
import SenseVoiceCore

struct StorageView: View {
    @EnvironmentObject private var locations: ExportLocations
    @EnvironmentObject private var drive: GoogleDriveService
    @EnvironmentObject private var model: AppModel
    @State private var showFolderPicker = false
    @State private var deleting: URL?
    @State private var error: String?
    var body: some View {
        List {
            Section("Google Drive") {
                if let account = drive.account {
                    Label(account, systemImage: "checkmark.circle.fill")
                    Text("文字上传到：我的云端硬盘 / 声笺。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("打开 Google Drive 文件夹列表", destination: URL(string: "https://drive.google.com/drive/my-drive")!)
                    Button("断开账号") { drive.signOut() }.disabled(drive.busy)
                } else if drive.configured {
                    GoogleSignInButton { drive.connectFromButton() }.disabled(drive.busy || model.busy)
                    Text("连接一次后，导出时可直接上传 Markdown，不用逐层选择位置。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("Google Drive 待配置", systemImage: "cloud")
                    Text("需要为本 App 配置 Google iOS OAuth Client ID。配置完成后可连接账号并直接上传，不需要安装 Google Drive App。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if drive.busy { ProgressView("正在连接…") }
            }
            Section("常用保存文件夹") {
                Label(locations.folderName ?? "尚未选择", systemImage: "folder")
                Button(locations.folderName == nil ? "选择常用文件夹" : "更换文件夹") { showFolderPicker = true }
                if locations.folderName != nil { Button("清除常用位置") { locations.forget() } }
                Text("只需选一次，之后导出可直接保存。部分云盘不允许选择文件夹时，可使用 Google Drive 直接上传或系统保存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("本机 Markdown 文件（\(locations.files.count)）") {
                Text("文件 App → 我的 iPhone → 声笺 → Transcripts")
                    .font(.caption).foregroundStyle(.secondary)
                if locations.files.isEmpty { Text("导出时选择「保存到本机」，文件会显示在这里。").foregroundStyle(.secondary) }
                ForEach(locations.files, id: \.path) { url in
                    NavigationLink { MarkdownFileDetail(url: url) } label: {
                        Label(url.lastPathComponent, systemImage: "doc.text")
                    }.swipeActions {
                        Button("删除文件", role: .destructive) { deleting = url }
                    }
                }
            }
            Section("录音保存位置") {
                Text("录音停止后直接进入资料库详情，原始声音自动保存在本机。")
                Text("文件 App → 我的 iPhone → 声笺 → Recordings")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("文件与云盘")
        .onAppear { locations.refresh() }
        .refreshable { locations.refresh() }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker(onSelect: { url in
                do { try locations.remember(url) } catch { self.error = error.localizedDescription }
                showFolderPicker = false
            }, onCancel: { showFolderPicker = false })
        }
        .confirmationDialog("删除本机 Markdown 文件？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除文件", role: .destructive) {
                if let url = deleting {
                    do { try locations.delete(url) } catch { self.error = error.localizedDescription }
                }
                deleting = nil
            }
        } message: { Text("录音和资料库中的转录文字会保留；云盘副本不受影响。") }
        .alert("提示", isPresented: Binding(get: { error != nil || drive.error != nil }, set: { if !$0 { error = nil; drive.error = nil } })) {
            Button("知道了") { error = nil; drive.error = nil }
        } message: { Text(error ?? drive.error ?? "") }
    }
}

struct MarkdownFileDetail: View {
    let url: URL
    @EnvironmentObject private var locations: ExportLocations
    @EnvironmentObject private var drive: GoogleDriveService
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var deleting = false
    @State private var uploading = false
    @State private var uploadedURL: URL?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(url.lastPathComponent).font(.headline)
                ShareLink(item: url) { Label("分享 Markdown 文件", systemImage: "square.and.arrow.up") }
                Button("上传到 Google Drive", systemImage: "cloud") {
                    uploading = true
                    Task {
                        defer { uploading = false }
                        do { uploadedURL = try await drive.upload(text: text, filename: url.lastPathComponent).viewURL }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(!drive.configured || uploading || drive.busy || text.isEmpty)
                if uploading { ProgressView("正在上传…") }
                if let uploadedURL { Link("查看 Google Drive 文件", destination: uploadedURL) }
                Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button("删除本机文件", role: .destructive) { deleting = true }.disabled(uploading)
            }.padding()
        }.navigationTitle("Markdown 文件").navigationBarTitleDisplayMode(.inline)
            .task {
                do { text = try String(contentsOf: url, encoding: .utf8) }
                catch { self.error = error.localizedDescription }
            }
            .confirmationDialog("删除本机文件？录音和转录文字会保留。", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除文件", role: .destructive) {
                    do { try locations.delete(url); dismiss() } catch { self.error = error.localizedDescription }
                }
            }
            .alert("操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("知道了") { error = nil }
            } message: { Text(error ?? "") }
    }
}

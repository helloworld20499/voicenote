import SwiftUI
import UIKit
import SenseVoiceCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = 0
    @State private var path: [UUID] = []
    @State private var deleteRecord: Recording?
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var exportSelection: ExportSelection?
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { recorderView }
                .tabItem { Label("录音", systemImage: "mic.fill") }.tag(0)
            NavigationStack(path: $path) {
                libraryView.navigationDestination(for: UUID.self) { RecordingDetail(id: $0) }
            }
                .tabItem { Label("资料库", systemImage: "text.badge.waveform") }.tag(1)
        }
        .onChange(of: model.lastSavedID) { _, id in
            if let id { selecting = false; selectedIDs.removeAll(); tab = 1; path = [id] }
        }
        .alert("提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var recorderView: some View {
        VStack(spacing: 28) {
            Spacer()
            if model.isRecording {
                Text(timerText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Button { model.isRecording ? model.stopRecording() : model.startRecording() } label: {
                Label(model.isRecording ? "停止并保存" : "开始录音", systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.downloading || model.transcribingID != nil || model.requestingPermission)
            Spacer()
        }.padding(32)
            .navigationTitle("录音").navigationBarTitleDisplayMode(.inline)
    }
    private var timerText: String { String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60) }
    private var libraryView: some View {
        List {
            if visibleRecords.isEmpty {
                ContentUnavailableView("还没有录音", systemImage: "waveform", description: Text("录制的声音会保存在这里。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(visibleRecords) { record in
                if selecting {
                    Button {
                        if !selectedIDs.insert(record.id).inserted { selectedIDs.remove(record.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(.orange)
                            recordRow(record)
                        }
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(record.title)，\(selectedIDs.contains(record.id) ? "已选择" : "未选择")")
                } else {
                    NavigationLink(value: record.id) { recordRow(record) }
                         .swipeActions {
                            Button("删除记录", role: .destructive) { deleteRecord = record }.disabled(model.busy)
                        }
                }
            }
        }
        .navigationTitle("资料库")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if selecting {
                    Button(selectedIDs.count == visibleRecords.count ? "取消全选" : "全选") {
                        selectedIDs = selectedIDs.count == visibleRecords.count ? [] : Set(visibleRecords.map(\.id))
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !selecting {
                    Menu {
                        Button("导出今天的文字") {
                            exportSelection = ExportSelection(records: model.recordings.filter { Calendar.current.isDateInToday($0.createdAt) })
                        }.disabled(!model.recordings.contains { Calendar.current.isDateInToday($0.createdAt) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        Button("导出全部文字") { exportSelection = ExportSelection(records: model.recordings) }
                            .disabled(RecordingTextExport.exportable(model.recordings).isEmpty)
                    } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("导出文字")
                        .disabled(model.busy)
                }
                Button(selecting ? "取消" : "选择") {
                    selecting.toggle(); selectedIDs.removeAll()
                }.disabled(model.recordings.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Text("已选 \(selectedIDs.count) 条").font(.subheadline)
                    Spacer()
                    Button("导出文字", systemImage: "square.and.arrow.up") {
                        exportSelection = ExportSelection(records: model.recordings.filter { selectedIDs.contains($0.id) })
                    }.buttonStyle(.borderedProminent)
                        .disabled(model.busy || RecordingTextExport.exportable(model.recordings.filter { selectedIDs.contains($0.id) }).isEmpty)
                }.padding().background(.bar)
            }
        }
        .refreshable { model.reloadRecordings() }
        .confirmationDialog("删除录音和转录文字？", isPresented: Binding(get: { deleteRecord != nil }, set: { if !$0 { deleteRecord = nil } }), titleVisibility: .visible) {
            Button("删除整条记录", role: .destructive) {
                if let record = deleteRecord { model.delete(record) }
                deleteRecord = nil
            }
            Button("取消", role: .cancel) { deleteRecord = nil }
        }
        .sheet(item: $exportSelection) { selection in TextExportView(records: selection.records) }
    }
    private var visibleRecords: [Recording] {
        model.recordings
    }
    private func recordRow(_ record: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(record.title).font(.headline); Spacer(); Text("\(Int(record.duration)) 秒").font(.caption).foregroundStyle(.secondary) }
            Text(record.text.isEmpty ? "尚未转录" : record.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }.foregroundStyle(.primary).padding(.vertical, 6)
    }

}

struct RecordingDetail: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var deletingText = false
    @State private var deletingRecord = false
    @State private var draft = ""
    @State private var editing = false
    @State private var exportSelection: ExportSelection?
    private var record: Recording? { model.recordings.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 20) {
                    Text(record.title).font(.title2.bold())
                    HStack {
                        Label("\(Int(record.duration)) 秒", systemImage: "waveform")
                        if let seconds = record.processingDuration { Text(String(format: "转录耗时 %.1f 秒", seconds)) }
                    }.font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { model.togglePlayback(record) } label: {
                            Label(model.playingID == id ? "停止播放" : "播放录音", systemImage: model.playingID == id ? "stop.fill" : "play.fill")
                        }.disabled(model.busy)
                    }.buttonStyle(.bordered)
                    if model.transcribingID == id {
                        ProgressView(value: model.transcriptionProgress)
                        Text("正在离线转录…").foregroundStyle(.secondary)
                    }
                    if editing {
                        TextEditor(text: $draft).frame(minHeight: 280).padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        HStack {
                            Button("取消") { editing = false }
                            Spacer()
                            Button("保存文字") { model.updateText(id, text: draft); editing = false }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        Text(record.text.isEmpty ? "尚无转录文字。可以点击下面的按钮转录。" : record.text)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        HStack {
                            Button("复制文字", systemImage: "doc.on.doc") { UIPasteboard.general.string = record.text }
                            Spacer()
                            Button("编辑", systemImage: "pencil") { draft = record.text; editing = true }
                        }.disabled(record.text.isEmpty || model.busy)
                        if !record.text.isEmpty {
                            Button { exportSelection = ExportSelection(records: [record]) } label: {
                                Label("导出文字", systemImage: "folder")
                            }.buttonStyle(.borderedProminent).disabled(model.busy)
                            Button("删除转录文字", role: .destructive) { deletingText = true }
                                .disabled(model.busy)
                        }
                        if !model.modelReady {
                            if model.downloading {
                                ProgressView(value: model.downloadProgress)
                                Text("正在下载离线模型… \(Int(model.downloadProgress * 100))%")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Button("下载离线模型（239 MB）") { model.downloadModel() }
                                    .buttonStyle(.bordered).disabled(model.busy)
                            }
                        }
                        Button(record.processingDuration == nil ? "转录这段录音" : "重新转录（覆盖当前文字）") { model.transcribeRecording(id) }
                            .buttonStyle(.bordered).disabled(model.busy || !model.modelReady)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("录音位置：文件 App → 我的 iPhone → 声笺 → Recordings")
                        Text(record.filename).textSelection(.enabled)
                    }.font(.caption).foregroundStyle(.secondary)
                    Button("删除这条录音及文字", role: .destructive) { deletingRecord = true }.disabled(model.busy)
                    Text("音频保存在本机。导出仅包含 Markdown 文字；已导出的副本可在系统「文件」App 中管理。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
        }.navigationTitle("录音详情").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("删除转录文字？", isPresented: $deletingText, titleVisibility: .visible) {
                Button("删除文字，保留录音", role: .destructive) { model.deleteTranscript(id) }
            } message: { Text("可再次转录。已导出的本机或云盘副本不会被删除。") }
            .confirmationDialog("删除这条录音及文字？", isPresented: $deletingRecord, titleVisibility: .visible) {
                Button("删除整条记录", role: .destructive) {
                    if let record { model.delete(record); if !model.recordings.contains(where: { $0.id == id }) { dismiss() } }
                }
            }
            .sheet(item: $exportSelection) { selection in TextExportView(records: selection.records) }
    }
}

import SwiftUI
import UIKit
import SenseVoiceCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var exportSelection: ExportSelection?
    var body: some View {
        TabView {
            NavigationStack { recorderView }
                .tabItem { Label("录音", systemImage: "mic.fill") }
            NavigationStack { libraryView }
                .tabItem { Label("我的录音", systemImage: "text.badge.waveform") }
        }
        .alert("提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var recorderView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("把声音，留成文字。")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("中文与英文 · SenseVoice Small · 本机转录")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 12)
                VStack(alignment: .leading, spacing: 14) {
                    Label(model.modelReady ? "离线模型已就绪" : "录音不需要先下载模型", systemImage: model.modelReady ? "checkmark.shield.fill" : "arrow.down.circle.fill")
                        .font(.headline).foregroundStyle(model.modelReady ? .green : .primary)
                    Text(model.modelReady ? "关闭网络后也可以录音和转文字。" : "可以先录音保存；需要转文字时再下载约 239 MB 的模型。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if model.downloading {
                        ProgressView(value: model.downloadProgress)
                        Text("正在下载并校验… \(Int(model.downloadProgress * 100))%")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    } else if !model.modelReady {
                        Button("下载 SenseVoice 模型") { model.downloadModel() }
                            .buttonStyle(.borderedProminent).disabled(model.busy)
                    }
                }.padding(20).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                VStack(spacing: 18) {
                    Image(systemName: model.isRecording ? "waveform" : "waveform.circle")
                        .font(.system(size: 62)).foregroundStyle(.orange)
                        .symbolEffect(.variableColor, isActive: model.isRecording)
                    Text(model.isRecording ? timerText : "准备好，就开始说吧")
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(model.isRecording ? "正在录音，点击停止后保存" : "先录音保存，需要时再转成文字。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { model.isRecording ? model.stopRecording() : model.startRecording() } label: {
                        Label(model.isRecording ? "停止并保存" : "开始录音", systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.downloading || model.transcribingID != nil || model.requestingPermission)
                    if model.transcribingID != nil {
                        ProgressView(value: model.transcriptionProgress)
                        Text("正在本机识别，首次加载模型可能稍慢…").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity).padding(24)
                    .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 26))
                if let notice = model.notice { Label(notice, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary) }
                if let latest = model.recordings.first {
                    NavigationLink { RecordingDetail(id: latest.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text("最近一次录音").font(.headline); Spacer(); Image(systemName: "arrow.up.right") }
                            Text(latest.text.isEmpty ? "录音已保存，点击查看。" : latest.text).font(.subheadline).lineLimit(4)
                            Text(latest.title).font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary).padding(20)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
                Text("开始录音后可切换 App 或锁屏，返回后点击停止保存。来电等系统中断会停止录音。转录请在前台进行，后台录音效果待真机验证。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("声笺").navigationBarTitleDisplayMode(.inline)
    }
    private var timerText: String { String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60) }
    private var libraryView: some View {
        List {
            if model.recordings.isEmpty {
                ContentUnavailableView("还没有录音", systemImage: "waveform", description: Text("录制第一段声音，音频与文字会保存在这里。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(model.recordings) { record in
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
                    NavigationLink { RecordingDetail(id: record.id) } label: { recordRow(record) }
                        .swipeActions { Button("删除", role: .destructive) { model.delete(record) }.disabled(model.busy) }
                }
            }
        }
        .navigationTitle("我的录音")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if selecting {
                    Button(selectedIDs.count == model.recordings.count ? "取消全选" : "全选") {
                        selectedIDs = selectedIDs.count == model.recordings.count ? [] : Set(model.recordings.map(\.id))
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
        .sheet(item: $exportSelection) { selection in TextExportView(records: selection.records) }
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
                                Label("导出文字到文件 / 云盘", systemImage: "folder")
                            }.buttonStyle(.borderedProminent).disabled(model.busy)
                            ShareLink(item: record.text) { Label("分享文字", systemImage: "square.and.arrow.up") }
                        }
                        if !model.modelReady {
                            Text("录音已保存。请先在录音页下载离线模型，再回来转录。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button(record.processingDuration == nil ? "转录这段录音" : "重新转录（覆盖当前文字）") { model.transcribeRecording(id) }
                            .buttonStyle(.bordered).disabled(model.busy || !model.modelReady)
                    }
                    Text("音频和文字保存在本机。文字文件可手动保存到本机或云盘，导出文字不会包含音频。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
        }.navigationTitle("录音详情").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $exportSelection) { selection in TextExportView(records: selection.records) }
    }
}

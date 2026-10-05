import Foundation

public struct Recording: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let filename: String
    public var duration: Double
    public var text: String
    public var processingDuration: Double?
    public var title: String { createdAt.formatted(date: .abbreviated, time: .shortened) }
    public init(id: UUID, createdAt: Date, filename: String, duration: Double, text: String, processingDuration: Double? = nil) {
        self.id = id; self.createdAt = createdAt; self.filename = filename
        self.duration = duration; self.text = text; self.processingDuration = processingDuration
    }
}

public enum RecordingTextExport {
    public static func exportable(_ records: [Recording]) -> [Recording] {
        records.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
    }
    public static func contents(_ records: [Recording], timeZone: TimeZone = .current) throws -> String {
        let records = exportable(records)
        guard !records.isEmpty else { throw PrototypeError.message("所选记录尚无文字，请先转录再导出。") }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone; dayFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone; timeFormatter.dateFormat = "HH:mm:ss ZZZZZ"
        var lines = ["# 声笺 · 想法记录", "", "时区：\(timeZone.identifier)", "记录数：\(records.count)", ""]
        var previousDay = ""
        for record in records {
            let day = dayFormatter.string(from: record.createdAt)
            if day != previousDay {
                lines += ["## \(day)", ""]
                previousDay = day
            }
            let time = timeFormatter.string(from: record.createdAt)
            lines += ["### \(time)", "", record.text, ""]
        }
        // Preserve the user's complete edited transcript without rewriting it.
        return lines.joined(separator: "\n")
    }
    public static func filename(_ records: [Recording], timeZone: TimeZone = .current) throws -> String {
        let records = exportable(records)
        guard let first = records.first, let last = records.last else { throw PrototypeError.message("没有可以导出的文字。") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: first.createdAt); let end = formatter.string(from: last.createdAt)
        let dates = start == end ? start : "\(start)_\(end)"
        return "声笺_\(dates).md"
    }
}

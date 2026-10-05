import XCTest
@testable import SenseVoiceCore

final class TextExportTests: XCTestCase {
    private let zone = TimeZone(secondsFromGMT: -7 * 3600)!
    private func record(_ timestamp: String, text: String) -> Recording {
        Recording(id: UUID(), createdAt: ISO8601DateFormatter().date(from: timestamp)!, filename: "private.wav", duration: 10, text: text)
    }
    func testSelectedEditedTextIsPreservedAndOrderedByLocalDate() throws {
        let first = record("2026-10-05T06:55:00Z", text: "  今天测试 API。\n\n第二段：hello，世界。  ")
        let second = record("2026-10-05T07:05:00Z", text: "明天继续。")
        let ignored = record("2026-10-05T06:00:00Z", text: " \n ")
        let markdown = try RecordingTextExport.contents([second, ignored, first], timeZone: zone)
        XCTAssertTrue(markdown.contains("## 2026-10-04"))
        XCTAssertTrue(markdown.contains("## 2026-10-05"))
        XCTAssertTrue(markdown.contains("### 23:55:00 -07:00"))
        XCTAssertTrue(markdown.contains(first.text))
        XCTAssertLessThan(markdown.range(of: first.text)!.lowerBound, markdown.range(of: second.text)!.lowerBound)
        XCTAssertTrue(markdown.contains("记录数：2"))
        XCTAssertFalse(markdown.contains("private.wav"))
        XCTAssertEqual(try RecordingTextExport.filename([second, first], timeZone: zone), "声笺_2026-10-04_2026-10-05.md")
    }
    func testMarkdownIncludesOnlySelectedRecordsAndRoundTripsUTF8() throws {
        let chosen = record("2026-10-05T01:00:00Z", text: "选择的想法 📝\nEnglish + 中文")
        let result = try RecordingTextExport.contents([chosen], timeZone: zone)
        XCTAssertEqual(String(data: Data(result.utf8), encoding: .utf8), result)
        XCTAssertTrue(result.contains("## 2026-10-04"))
        XCTAssertTrue(result.contains(chosen.text))
        XCTAssertTrue(result.contains("# 声笺"))
        XCTAssertEqual(try RecordingTextExport.filename([chosen], timeZone: zone), "声笺_2026-10-04.md")
    }
    func testEmptyTranscriptsCannotProduceMisleadingExport() {
        XCTAssertThrowsError(try RecordingTextExport.contents([]))
        XCTAssertThrowsError(try RecordingTextExport.contents([record("2026-10-05T01:00:00Z", text: " \n ")]))
    }
    func testExistingRecordingJSONRemainsReadable() throws {
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000001","createdAt":100,"filename":"old.wav","duration":5,"text":"旧记录"}
        """
        let result = try JSONDecoder().decode(Recording.self, from: Data(legacy.utf8))
        XCTAssertEqual(result.text, "旧记录")
        XCTAssertNil(result.processingDuration)
    }
}

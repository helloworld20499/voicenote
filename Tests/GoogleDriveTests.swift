import XCTest
@testable import SenseVoiceCore

private final class DriveMockProtocol: URLProtocol {
    static var responses: [(Int, String)] = []
    static var requests: [URLRequest] = []
    static var bodies: [Data] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.bodies.append(body)
        let result = Self.responses.isEmpty ? (500, "{}") : Self.responses.removeFirst()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GoogleDriveTests: XCTestCase {
    private func client(_ responses: [(Int, String)]) -> GoogleDriveClient {
        DriveMockProtocol.responses = responses; DriveMockProtocol.requests = []; DriveMockProtocol.bodies = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DriveMockProtocol.self]
        return GoogleDriveClient(session: URLSession(configuration: configuration))
    }
    func testCreatesFolderAndUploadsMarkdownWithUnicodeAndNoAudio() async throws {
        let client = client([(200, "{\"files\":[]}"), (200, "{\"id\":\"folder1\"}"),
                             (200, "{\"id\":\"file1\",\"name\":\"声笺.md\",\"webViewLink\":\"https://drive.google.com/file/d/file1/view\"}")])
        let text = "# 今天\n中文 English 😀"
        let file = try await client.uploadMarkdown(text: text, filename: "声笺.md", token: "test-token")
        XCTAssertEqual(file.id, "file1")
        XCTAssertEqual(DriveMockProtocol.requests.count, 3)
        let folder = DriveMockProtocol.bodies[1]
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: folder) as? [String: Any])
        XCTAssertEqual(metadata["mimeType"] as? String, "application/vnd.google-apps.folder")
        let upload = DriveMockProtocol.requests[2]
        XCTAssertEqual(upload.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(upload.httpMethod, "POST")
        XCTAssertEqual(upload.url?.host, "www.googleapis.com")
        let contents = String(data: DriveMockProtocol.bodies[2], encoding: .utf8)!
        XCTAssertTrue(contents.contains(text)); XCTAssertTrue(contents.contains("folder1"))
        XCTAssertTrue(contents.contains("text/markdown")); XCTAssertFalse(contents.contains(".wav"))
    }
    func testExistingAppFolderIsReused() async throws {
        let client = client([(200, "{\"files\":[{\"id\":\"existing\"}]}"), (200, "{\"id\":\"uploaded\"}")])
        _ = try await client.uploadMarkdown(text: "saved", filename: "test.md", token: "test")
        XCTAssertEqual(DriveMockProtocol.requests.count, 2)
        XCTAssertEqual(DriveMockProtocol.requests.first?.httpMethod, "GET")
    }
    func testPermissionFailureStopsBeforeUploading() async {
        let client = client([(403, "{\"error\":{\"message\":\"private server details\"}}")])
        do {
            _ = try await client.uploadMarkdown(text: "private thoughts", filename: "test.md", token: "test")
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("拒绝访问"))
            XCTAssertFalse(error.localizedDescription.contains("private server details"))
            XCTAssertEqual(DriveMockProtocol.requests.count, 1)
        }
    }
}

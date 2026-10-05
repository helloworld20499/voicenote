import Foundation

public struct DriveFile: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let webViewLink: URL?
    public var viewURL: URL? {
        webViewLink ?? URL(string: "https://drive.google.com/file/d/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/view")
    }
}

public struct GoogleDriveClient: Sendable {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func uploadMarkdown(text: String, filename: String, token: String) async throws -> DriveFile {
        let folder = try await ensureFolder(token: token)
        let boundary = "VoiceNote-\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: ["name": filename, "mimeType": "text/markdown", "parents": [folder.id]])
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append(metadata)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: text/markdown; charset=UTF-8\r\n\r\n".utf8))
        body.append(Data(text.utf8))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink")!)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return try await send(request, token: token)
    }
    private func ensureFolder(token: String) async throws -> DriveFile {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "trashed = false and mimeType = 'application/vnd.google-apps.folder' and appProperties has { key='voiceNoteRoot' and value='1' }"),
            URLQueryItem(name: "fields", value: "files(id,name,webViewLink)"), URLQueryItem(name: "pageSize", value: "1")
        ]
        struct Listing: Decodable { let files: [DriveFile] }
        let listing: Listing = try await send(URLRequest(url: components.url!), token: token)
        if let folder = listing.files.first { return folder }
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id,name,webViewLink")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": "声笺", "mimeType": "application/vnd.google-apps.folder", "appProperties": ["voiceNoteRoot": "1"]])
        return try await send(request, token: token)
    }
    private func send<T: Decodable>(_ input: URLRequest, token: String) async throws -> T {
        var request = input
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PrototypeError.message("Google Drive 没有返回有效响应。") }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401: throw PrototypeError.message("Google 登录已失效，请重新连接后重试。")
            case 403: throw PrototypeError.message("Google Drive 拒绝访问。请确认已授权 Drive、启用 Drive API，并检查存储空间。")
            case 429: throw PrototypeError.message("Google Drive 请求过多，请稍后重试。")
            default: throw PrototypeError.message("Google Drive 上传失败（\(http.statusCode)），本机文字仍保留。")
            }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

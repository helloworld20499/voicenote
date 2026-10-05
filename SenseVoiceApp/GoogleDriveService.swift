import SwiftUI
import GoogleSignIn
import SenseVoiceCore

@MainActor final class GoogleDriveService: ObservableObject {
    @Published var account: String?
    @Published var busy = false
    @Published var error: String?
    private let scope = "https://www.googleapis.com/auth/drive.file"
    var configured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              id.hasSuffix(".apps.googleusercontent.com"), !id.contains("YOUR_") else { return false }
        let reversed = id.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(reversed) == true }
    }
    func restore() async {
        guard configured, !busy, account == nil, GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        busy = true; defer { busy = false }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            account = user.profile?.email ?? "Google 账号"
        } catch { account = nil }
    }
    func connect() async throws {
        guard configured else { throw PrototypeError.message("Google Drive 尚未配置。请按 GOOGLE_DRIVE_SETUP.md 设置 iOS OAuth Client ID。") }
        guard let controller = presentingController() else { throw PrototypeError.message("请回到 App 后连接 Google Drive。") }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller, hint: nil, additionalScopes: [scope])
        guard result.user.grantedScopes?.contains(scope) == true else { throw PrototypeError.message("需要允许访问声笺创建的 Drive 文件，才能上传文字。") }
        account = result.user.profile?.email ?? "Google 账号"
    }
    func upload(text: String, filename: String) async throws -> DriveFile {
        guard !busy else { throw PrototypeError.message("Google Drive 正在处理，请稍后重试。") }
        busy = true; defer { busy = false }
        if GIDSignIn.sharedInstance.currentUser == nil { try await connect() }
        guard var user = GIDSignIn.sharedInstance.currentUser else { throw PrototypeError.message("请先连接 Google Drive。") }
        if user.grantedScopes?.contains(scope) != true {
            guard let controller = presentingController() else { throw PrototypeError.message("请回到 App 后授权。") }
            user = try await user.addScopes([scope], presenting: controller).user
        }
        guard user.grantedScopes?.contains(scope) == true else { throw PrototypeError.message("未获得 Google Drive 上传权限。") }
        let refreshed = try await user.refreshTokensIfNeeded()
        account = refreshed.profile?.email ?? "Google 账号"
        return try await GoogleDriveClient().uploadMarkdown(text: text, filename: filename, token: refreshed.accessToken.tokenString)
    }
    func signOut() {
        guard !busy else { return }
        GIDSignIn.sharedInstance.signOut(); account = nil
    }
    func connectFromButton() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { try await connect() }
            catch { if !Self.isCancellation(error) { self.error = error.localizedDescription } }
        }
    }
    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        // Google Sign-In's public kGIDSignInErrorCodeCanceled is -5.
        return error.domain == kGIDSignInErrorDomain && error.code == -5
    }
    private func presentingController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var controller = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let next = controller?.presentedViewController { controller = next }
        return controller
    }
}

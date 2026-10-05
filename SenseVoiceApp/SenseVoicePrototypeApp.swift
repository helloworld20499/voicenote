import SwiftUI
import GoogleSignIn

@main struct SenseVoicePrototypeApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var locations = ExportLocations()
    @StateObject private var drive = GoogleDriveService()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model).environmentObject(locations).environmentObject(drive)
                .task { await drive.restore() }
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .tint(.orange)
                .onChange(of: scenePhase) { _, phase in if phase == .background { model.wentToBackground() } }
        }
    }
}

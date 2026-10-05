import SwiftUI

@main struct SenseVoicePrototypeApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .tint(.orange)
                .onChange(of: scenePhase) { _, phase in if phase == .background { model.wentToBackground() } }
        }
    }
}

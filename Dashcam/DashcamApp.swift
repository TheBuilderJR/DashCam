import SwiftUI

@main
struct DashcamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Dashcam", systemImage: "video.circle.fill") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Snapshots", id: "snapshots") {
            SnapshotListView()
                .environmentObject(appState)
        }
    }
}


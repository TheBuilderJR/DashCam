import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Circle()
                    .fill(appState.isRecording ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                Text(appState.statusText)
                    .font(.headline)
            }

            // Permissions
            if !appState.allPermissionsGranted {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Permissions Needed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)

                    PermissionRow(
                        name: "Screen Recording",
                        granted: appState.screenRecordingGranted
                    ) {
                        openPrivacyPane("Privacy_ScreenCapture")
                    }
                    PermissionRow(
                        name: "Microphone",
                        granted: appState.microphoneGranted
                    ) {
                        appState.requestMicrophoneAccess()
                    }

                    Button("Refresh") {
                        appState.refreshPermissions()
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
            }

            Divider()

            // Record toggle
            Button(appState.isRecording ? "Stop Recording" : "Start Recording") {
                if appState.isRecording {
                    appState.stopRecording()
                } else {
                    appState.startRecording()
                }
            }
            .keyboardShortcut("r", modifiers: [.command])

            // Snapshot
            HStack {
                Button("Take Snapshot") {
                    appState.takeSnapshot()
                }
                .disabled(!appState.isRecording)
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Picker("", selection: $appState.snapshotDuration) {
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                    Text("30 min").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                    Text("2 hours").tag(TimeInterval(7200))
                }
                .fixedSize()
                .disabled(!appState.isRecording)
            }

            Divider()

            // Open snapshots
            Button("View Snapshots...") {
                // Try SwiftUI openWindow first, fall back to NSApp window activation
                openWindow(id: "snapshots")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.title == "Snapshots" {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
            .keyboardShortcut("l", modifiers: [.command])

            Divider()

            Button("Quit Dashcam") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding()
        .frame(width: 220)
        .onAppear {
            appState.refreshPermissions()
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        )
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool
    var hint: String? = nil
    let grantAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? .green : .red)
                    .font(.caption)
                Text(name)
                    .font(.caption)
                Spacer()
                if !granted {
                    Button("Grant") { grantAction() }
                        .font(.caption)
                        .controlSize(.mini)
                }
            }
            if !granted, let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
    }
}

// AppDelegate — close the Snapshots window that SwiftUI opens on launch
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "Snapshots" {
                window.close()
            }
        }
    }
}

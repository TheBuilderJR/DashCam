import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var statusText = "Idle"
    @Published var snapshotDuration: TimeInterval = 300

    @Published var screenRecordingGranted = false
    @Published var microphoneGranted = false

    var allPermissionsGranted: Bool {
        screenRecordingGranted && microphoneGranted
    }

    func refreshPermissions() {
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = status == .authorized
    }

    func requestMicrophoneAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphoneGranted = granted
                }
            }
        } else {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            )
        }
    }

    let screenRecorder = ScreenRecorder()
    let ringBufferManager = RingBufferManager()
    let clipboardMonitor = ClipboardMonitor()
    let snapshotManager = SnapshotManager()
    let videoExporter = VideoExporter()

    func startRecording() {
        Task {
            do {
                // Wire up dependencies
                screenRecorder.ringBufferManager = ringBufferManager

                clipboardMonitor.onClipboardChange = { [weak self] event in
                    self?.ringBufferManager.addClipboardEvent(event)
                }

                // Start services
                try ringBufferManager.start()
                try await screenRecorder.start()
                clipboardMonitor.start()

                isRecording = true
                statusText = "Recording"
                refreshPermissions()
            } catch is ScreenRecorderError {
                statusText = "Grant Screen Recording in System Settings, then restart"
            } catch {
                statusText = "Error: \(error.localizedDescription)"
                print("[AppState] Failed to start: \(error)")
            }
        }
    }

    func stopRecording() {
        Task {
            await screenRecorder.stop()
            ringBufferManager.stop()
            clipboardMonitor.stop()

            isRecording = false
            statusText = "Stopped"
        }
    }

    func takeSnapshot() {
        statusText = "Creating snapshot..."
        let duration = snapshotDuration
        Task.detached { [weak self] in
            guard let self else { return }
            let snapshot = self.snapshotManager.createSnapshot(from: self.ringBufferManager, maxDuration: duration)
            await MainActor.run {
                if snapshot != nil {
                    self.statusText = "Snapshot created"
                } else {
                    self.statusText = "Snapshot failed"
                }
                // Resume recording after flush
                if self.isRecording {
                    try? self.ringBufferManager.start()
                }
            }
        }
    }
}

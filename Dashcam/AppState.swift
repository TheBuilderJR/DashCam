import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var statusText = "Idle"
    @Published var snapshotDuration: TimeInterval = 300

    @Published var captureSystemAudio: Bool = true
    @Published var captureMicrophone: Bool = true

    @Published var availableMicrophones: [AVCaptureDevice] = []
    @Published var selectedMicrophoneID: String = "" {
        didSet {
            UserDefaults.standard.set(selectedMicrophoneID, forKey: "selectedMicrophoneID")
        }
    }

    @Published var screenRecordingGranted = false
    @Published var microphoneGranted = false

    var allPermissionsGranted: Bool {
        screenRecordingGranted && microphoneGranted
    }

    func refreshPermissions() {
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = status == .authorized
        refreshMicrophones()
    }

    func refreshMicrophones() {
        availableMicrophones = MicrophoneCapturer.availableDevices()

        // Restore saved selection, or fall back to system default
        let savedID = UserDefaults.standard.string(forKey: "selectedMicrophoneID") ?? ""
        if availableMicrophones.contains(where: { $0.uniqueID == savedID }) {
            selectedMicrophoneID = savedID
        } else if let defaultMic = AVCaptureDevice.default(for: .audio) {
            selectedMicrophoneID = defaultMic.uniqueID
        } else if let first = availableMicrophones.first {
            selectedMicrophoneID = first.uniqueID
        }
    }

    var selectedMicrophone: AVCaptureDevice? {
        availableMicrophones.first { $0.uniqueID == selectedMicrophoneID }
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
    let microphoneCapturer = MicrophoneCapturer()

    func startRecording() {
        Task {
            do {
                // Wire up dependencies
                screenRecorder.ringBufferManager = ringBufferManager
                screenRecorder.captureSystemAudio = captureSystemAudio

                ringBufferManager.captureSystemAudio = captureSystemAudio
                ringBufferManager.captureMicrophone = captureMicrophone

                clipboardMonitor.onClipboardChange = { [weak self] event in
                    self?.ringBufferManager.addClipboardEvent(event)
                }

                // Start services
                try ringBufferManager.start()
                try await screenRecorder.start()
                clipboardMonitor.start()

                // Start microphone capture if enabled
                if captureMicrophone {
                    microphoneCapturer.onMicSample = { [weak self] sampleBuffer in
                        self?.ringBufferManager.appendMicSample(sampleBuffer)
                    }
                    do {
                        try microphoneCapturer.start(device: selectedMicrophone)
                    } catch {
                        print("[AppState] Mic capture failed: \(error)")
                    }
                }

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
            microphoneCapturer.stop()
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

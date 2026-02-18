import AVFoundation
import Foundation

final class MicrophoneCapturer: NSObject {
    enum Error: LocalizedError {
        case noMicrophoneFound
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .noMicrophoneFound: return "No microphone device found"
            case .cannotAddInput: return "Cannot add microphone input to capture session"
            case .cannotAddOutput: return "Cannot add audio output to capture session"
            }
        }
    }

    var onMicSample: ((CMSampleBuffer) -> Void)?

    private var captureSession: AVCaptureSession?
    private let outputQueue = DispatchQueue(label: "com.dashcam.mic", qos: .userInteractive)

    /// Returns all available audio input devices.
    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    func start(device: AVCaptureDevice? = nil) throws {
        let session = AVCaptureSession()

        guard let mic = device ?? AVCaptureDevice.default(for: .audio) else {
            throw Error.noMicrophoneFound
        }

        let input = try AVCaptureDeviceInput(device: mic)
        guard session.canAddInput(input) else {
            throw Error.cannotAddInput
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(output) else {
            throw Error.cannotAddOutput
        }
        session.addOutput(output)

        session.startRunning()
        self.captureSession = session
        print("[MicrophoneCapturer] Started with device: \(mic.localizedName)")
    }

    func stop() {
        captureSession?.stopRunning()
        captureSession = nil
        print("[MicrophoneCapturer] Stopped")
    }
}

extension MicrophoneCapturer: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onMicSample?(sampleBuffer)
    }
}

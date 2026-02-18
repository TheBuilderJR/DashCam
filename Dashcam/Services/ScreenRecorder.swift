import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class ScreenRecorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published var isRecording = false

    private var stream: SCStream?

    private let outputWidth = 1920
    private let outputHeight = 1080
    private let fps: Int = 15

    var ringBufferManager: RingBufferManager?

    private var frameCount = 0

    private let videoQueue = DispatchQueue(label: "com.dashcam.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.dashcam.audio", qos: .userInteractive)

    func start() async throws {
        // Pre-request screen capture access
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            throw ScreenRecorderError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            print("[ScreenRecorder] No displays found")
            return
        }

        // Single stream: main display + audio
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = outputWidth
        config.height = outputHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.capturesAudio = true
        config.sampleRate = 44100
        config.channelCount = 2

        let scStream = SCStream(filter: filter, configuration: config, delegate: self)

        // Register self as output for both video and audio
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        try await scStream.startCapture()
        self.stream = scStream

        await MainActor.run {
            isRecording = true
        }
        print("[ScreenRecorder] Started capturing display \(display.displayID) (\(display.width)x\(display.height) pts)")
    }

    func stop() async {
        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil

        await MainActor.run {
            isRecording = false
        }
        print("[ScreenRecorder] Stopped")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            handleVideoSample(sampleBuffer)
        case .audio:
            ringBufferManager?.appendAudioSample(sampleBuffer)
        @unknown default:
            break
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenRecorder] Stream stopped with error: \(error)")
    }

    // MARK: - Video Handling

    private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Always copy the pixel buffer — SCStream recycles IOSurface backing memory
        guard let copy = copyPixelBuffer(pixelBuffer) else { return }

        // Use SCStream's own presentation timestamp (same clock as audio)
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        frameCount += 1
        if frameCount % 60 == 1 {
            print("[ScreenRecorder] Frame #\(frameCount), PTS=\(CMTimeGetSeconds(pts))s")
        }

        ringBufferManager?.appendVideoSample(copy, presentationTime: pts)
    }

    private func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)

        var copy: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &copy)
        guard let dest = copy else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])

        let srcPlanes = CVPixelBufferGetPlaneCount(source)
        if srcPlanes > 0 {
            for plane in 0..<srcPlanes {
                let srcAddr = CVPixelBufferGetBaseAddressOfPlane(source, plane)
                let dstAddr = CVPixelBufferGetBaseAddressOfPlane(dest, plane)
                let srcBPR = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstBPR = CVPixelBufferGetBytesPerRowOfPlane(dest, plane)
                let h = CVPixelBufferGetHeightOfPlane(source, plane)
                if let s = srcAddr, let d = dstAddr {
                    for row in 0..<h {
                        memcpy(d + row * dstBPR, s + row * srcBPR, min(srcBPR, dstBPR))
                    }
                }
            }
        } else {
            let srcAddr = CVPixelBufferGetBaseAddress(source)
            let dstAddr = CVPixelBufferGetBaseAddress(dest)
            let srcBPR = CVPixelBufferGetBytesPerRow(source)
            let dstBPR = CVPixelBufferGetBytesPerRow(dest)
            if let s = srcAddr, let d = dstAddr {
                for row in 0..<height {
                    memcpy(d + row * dstBPR, s + row * srcBPR, min(srcBPR, dstBPR))
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(dest, [])
        CVPixelBufferUnlockBaseAddress(source, .readOnly)
        return dest
    }
}

enum ScreenRecorderError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Screen Recording permission required. Grant access in System Settings > Privacy & Security > Screen Recording, then restart the app."
    }
}

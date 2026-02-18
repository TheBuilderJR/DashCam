import AVFoundation
import Foundation

final class RingBufferManager {
    static let bufferDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dashcam/buffer", isDirectory: true)
    }()

    private let segmentDuration: TimeInterval = 300 // 5 minutes
    private let maxSegments = 24 // 2 hours total

    var captureSystemAudio: Bool = true
    var captureMicrophone: Bool = true

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var currentSegmentURL: URL?
    private var currentSegmentID: UUID?
    private var segmentStartTime: Date?
    private var segmentStartPTS: CMTime?
    private var sessionStarted = false
    private var isWriting = false
    private var videoFrameCount = 0
    private var droppedFrameCount = 0

    private var currentSidecar = SegmentSidecar(
        segmentID: UUID(),
        startTime: Date(),
        endTime: Date(),
        clipboardEvents: []
    )

    private let writerQueue = DispatchQueue(label: "com.dashcam.ringbuffer.writer")

    // Video settings
    private let videoWidth = 1920
    private let videoHeight = 1080
    private let fps: Int32 = 15

    var onSegmentCompleted: ((SegmentInfo) -> Void)?

    func start() throws {
        try FileManager.default.createDirectory(at: Self.bufferDirectory, withIntermediateDirectories: true)
        clearBuffer()
        try startNewSegment()
    }

    /// Remove all segment files from the buffer directory.
    func clearBuffer() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.bufferDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }

    func stop() {
        writerQueue.sync {
            finalizeCurrentSegment()
        }
    }

    func appendVideoSample(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        writerQueue.async { [weak self] in
            self?._appendVideoSample(pixelBuffer, presentationTime: presentationTime)
        }
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            self?._appendAudioSample(sampleBuffer)
        }
    }

    func appendMicSample(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            self?._appendMicSample(sampleBuffer)
        }
    }

    func addClipboardEvent(_ event: ClipboardEvent) {
        writerQueue.async { [weak self] in
            self?.currentSidecar.clipboardEvents.append(event)
        }
    }

    /// Flush the current segment and return all existing segment infos.
    func flushAndGetSegments() -> [SegmentInfo] {
        writerQueue.sync {
            finalizeCurrentSegment()
            return enumerateSegments()
        }
    }

    // MARK: - Private

    private func _appendVideoSample(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard isWriting, let writer = assetWriter else { return }

        if writer.status != .writing {
            print("[RingBuffer] Writer not in writing state: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "none")")
            return
        }

        // Start session on first video frame — aligns audio & video timestamps
        if !sessionStarted {
            writer.startSession(atSourceTime: presentationTime)
            segmentStartPTS = presentationTime
            sessionStarted = true
            print("[RingBuffer] Session started at PTS=\(CMTimeGetSeconds(presentationTime))s")
        }

        // Check if segment duration exceeded
        if let startPTS = segmentStartPTS {
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(presentationTime, startPTS))
            if elapsed >= segmentDuration {
                print("[RingBuffer] Segment duration \(elapsed)s exceeded, rotating")
                finalizeCurrentSegment()
                do {
                    try startNewSegment()
                    // Start new session on the NEW writer at current PTS
                    assetWriter?.startSession(atSourceTime: presentationTime)
                    segmentStartPTS = presentationTime
                    sessionStarted = true
                } catch {
                    print("[RingBuffer] Failed to start new segment: \(error)")
                    return
                }
            }
        }

        guard let input = videoInput, input.isReadyForMoreMediaData,
              let adaptor = pixelBufferAdaptor else {
            droppedFrameCount += 1
            if droppedFrameCount % 30 == 1 {
                print("[RingBuffer] Dropped frame (input not ready), total dropped: \(droppedFrameCount)")
            }
            return
        }
        let ok = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        videoFrameCount += 1
        if !ok {
            print("[RingBuffer] adaptor.append FAILED at PTS=\(CMTimeGetSeconds(presentationTime))s, writer status=\(writer.status.rawValue), error=\(writer.error?.localizedDescription ?? "none")")
        } else if videoFrameCount % 60 == 1 {
            print("[RingBuffer] Written frame #\(videoFrameCount)")
        }
    }

    private func _appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        // Don't append audio until the session has started (from first video frame)
        guard isWriting, sessionStarted,
              let writer = assetWriter, writer.status == .writing,
              let input = audioInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    private func _appendMicSample(_ sampleBuffer: CMSampleBuffer) {
        guard isWriting, sessionStarted,
              let writer = assetWriter, writer.status == .writing,
              let input = micInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    private func startNewSegment() throws {
        let segmentID = UUID()
        let filename = "\(segmentID.uuidString).mov"
        let url = Self.bufferDirectory.appendingPathComponent(filename)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        let adaptorAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: adaptorAttributes
        )

        writer.add(vInput)

        // System audio input (conditional)
        var aInput: AVAssetWriterInput?
        if captureSystemAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            aInput = input
        }

        // Microphone audio input (conditional)
        var mInput: AVAssetWriterInput?
        if captureMicrophone {
            let micSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            mInput = input
        }

        writer.startWriting()
        // Don't startSession here — defer to first video frame for correct timestamps

        self.assetWriter = writer
        self.videoInput = vInput
        self.audioInput = aInput
        self.micInput = mInput
        self.pixelBufferAdaptor = adaptor
        self.currentSegmentURL = url
        self.currentSegmentID = segmentID
        self.segmentStartTime = Date()
        self.segmentStartPTS = nil
        self.sessionStarted = false
        self.isWriting = true
        self.videoFrameCount = 0
        self.droppedFrameCount = 0

        self.currentSidecar = SegmentSidecar(
            segmentID: segmentID,
            startTime: Date(),
            endTime: Date(),
            clipboardEvents: []
        )

        print("[RingBuffer] Started segment \(filename)")
    }

    private func finalizeCurrentSegment() {
        guard isWriting, let writer = assetWriter else { return }
        isWriting = false

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        // Write sidecar
        if let segmentID = currentSegmentID, let startTime = segmentStartTime {
            var sidecar = currentSidecar
            sidecar = SegmentSidecar(
                segmentID: segmentID,
                startTime: startTime,
                endTime: Date(),
                clipboardEvents: sidecar.clipboardEvents
            )
            let sidecarURL = Self.bufferDirectory.appendingPathComponent("\(segmentID.uuidString).json")
            if let data = try? JSONEncoder().encode(sidecar) {
                try? data.write(to: sidecarURL)
            }

            // Notify
            if let url = currentSegmentURL {
                let duration = sidecar.endTime.timeIntervalSince(sidecar.startTime)
                let info = SegmentInfo(
                    id: segmentID,
                    filename: url.lastPathComponent,
                    sidecarFilename: "\(segmentID.uuidString).json",
                    startTime: startTime,
                    duration: duration
                )
                onSegmentCompleted?(info)
            }
        }

        pruneOldSegments()
        print("[RingBuffer] Finalized segment")
    }

    private func pruneOldSegments() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.bufferDirectory, includingPropertiesForKeys: [.creationDateKey])
        else { return }

        let movFiles = files
            .filter { $0.pathExtension == "mov" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da < db
            }

        if movFiles.count > maxSegments {
            let toDelete = movFiles.prefix(movFiles.count - maxSegments)
            for file in toDelete {
                try? fm.removeItem(at: file)
                let sidecar = file.deletingPathExtension().appendingPathExtension("json")
                try? fm.removeItem(at: sidecar)
                print("[RingBuffer] Pruned \(file.lastPathComponent)")
            }
        }
    }

    private func enumerateSegments() -> [SegmentInfo] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.bufferDirectory, includingPropertiesForKeys: [.creationDateKey])
        else { return [] }

        return files
            .filter { $0.pathExtension == "mov" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da < db
            }
            .compactMap { url -> SegmentInfo? in
                let stem = url.deletingPathExtension().lastPathComponent
                guard let segmentID = UUID(uuidString: stem) else { return nil }
                let sidecarURL = url.deletingPathExtension().appendingPathExtension("json")
                let duration: TimeInterval
                let startTime: Date
                if let data = try? Data(contentsOf: sidecarURL),
                   let sidecar = try? JSONDecoder().decode(SegmentSidecar.self, from: data)
                {
                    duration = sidecar.endTime.timeIntervalSince(sidecar.startTime)
                    startTime = sidecar.startTime
                } else {
                    duration = 0
                    startTime = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                }
                return SegmentInfo(
                    id: segmentID,
                    filename: url.lastPathComponent,
                    sidecarFilename: "\(stem).json",
                    startTime: startTime,
                    duration: duration
                )
            }
    }
}

import AVFoundation
import AppKit
import Foundation

final class VideoExporter: ObservableObject {
    @Published var isExporting = false
    @Published var progress: Double = 0

    func export(snapshot: Snapshot, completion: @escaping (Result<URL, Error>) -> Void) {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            completion(.failure(ExportError.compositionFailed))
            return
        }

        // Lazily created composition audio tracks — one per source track index
        var compositionAudioTracks: [AVMutableCompositionTrack] = []

        var currentTime = CMTime.zero

        for segment in snapshot.segments {
            let url = snapshot.directory.appendingPathComponent(segment.filename)
            let asset = AVURLAsset(url: url)

            do {
                // Use the video track's actual time range to skip any leading gap
                // caused by absolute PTS offset in the .mov container
                guard let srcVideo = asset.tracks(withMediaType: .video).first else { continue }
                let timeRange = srcVideo.timeRange
                guard timeRange.duration > .zero else { continue }

                try videoTrack.insertTimeRange(timeRange, of: srcVideo, at: currentTime)

                let audioTracks = asset.tracks(withMediaType: .audio)
                for (index, srcAudio) in audioTracks.enumerated() {
                    // Grow composition audio tracks as needed
                    while compositionAudioTracks.count <= index {
                        guard let newTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                            continue
                        }
                        compositionAudioTracks.append(newTrack)
                    }
                    try compositionAudioTracks[index].insertTimeRange(timeRange, of: srcAudio, at: currentTime)
                }

                currentTime = CMTimeAdd(currentTime, timeRange.duration)
            } catch {
                print("[VideoExporter] Failed to insert segment: \(error)")
            }
        }

        // Show save panel
        DispatchQueue.main.async { [weak self] in
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.mpeg4Movie]
            panel.nameFieldStringValue = "Dashcam-\(Self.dateFormatter.string(from: snapshot.createdAt)).mp4"

            guard panel.runModal() == .OK, let outputURL = panel.url else {
                completion(.failure(ExportError.cancelled))
                return
            }

            self?.performExport(composition: composition, to: outputURL, completion: completion)
        }
    }

    private func performExport(composition: AVMutableComposition, to outputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(ExportError.exportSessionFailed))
            return
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4

        DispatchQueue.main.async { self.isExporting = true }

        // Progress polling
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.progress = Double(session.progress)
            }
        }

        session.exportAsynchronously { [weak self] in
            timer.invalidate()
            DispatchQueue.main.async {
                self?.isExporting = false
                self?.progress = 0
            }
            switch session.status {
            case .completed:
                completion(.success(outputURL))
            case .failed:
                completion(.failure(session.error ?? ExportError.unknown))
            case .cancelled:
                completion(.failure(ExportError.cancelled))
            default:
                completion(.failure(ExportError.unknown))
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    enum ExportError: LocalizedError {
        case compositionFailed
        case exportSessionFailed
        case cancelled
        case unknown

        var errorDescription: String? {
            switch self {
            case .compositionFailed: return "Failed to create composition"
            case .exportSessionFailed: return "Failed to create export session"
            case .cancelled: return "Export cancelled"
            case .unknown: return "Unknown export error"
            }
        }
    }
}

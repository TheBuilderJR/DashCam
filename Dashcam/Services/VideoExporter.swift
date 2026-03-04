import AVFoundation
import AppKit
import Foundation

final class VideoExporter: ObservableObject {
    @Published var isExporting = false
    @Published var progress: Double = 0

    func export(snapshot: Snapshot, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let composition = CompositionBuilder.buildExportComposition(
            segments: snapshot.segments,
            directory: snapshot.directory
        ) else {
            completion(.failure(ExportError.compositionFailed))
            return
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

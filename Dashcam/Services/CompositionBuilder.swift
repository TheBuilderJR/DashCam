import AVFoundation

enum CompositionBuilder {
    /// Build a playback composition from segments in the given directory.
    /// Uses each video track's actual time range to skip leading PTS gaps.
    static func buildComposition(segments: [SegmentInfo], directory: URL) -> AVMutableComposition? {
        let composition = AVMutableComposition()
        var insertTime = CMTime.zero

        for segment in segments {
            let url = directory.appendingPathComponent(segment.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let asset = AVURLAsset(url: url)
            guard let videoTrack = asset.tracks(withMediaType: .video).first else { continue }
            let timeRange = videoTrack.timeRange
            guard timeRange.duration > .zero else { continue }
            do {
                try composition.insertTimeRange(timeRange, of: asset, at: insertTime)
                insertTime = CMTimeAdd(insertTime, timeRange.duration)
            } catch {
                continue
            }
        }

        return insertTime > .zero ? composition : nil
    }

    /// Build an export composition with separate video and audio tracks.
    /// Returns nil if no valid video content is found.
    static func buildExportComposition(segments: [SegmentInfo], directory: URL) -> AVMutableComposition? {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        var compositionAudioTracks: [AVMutableCompositionTrack] = []
        var currentTime = CMTime.zero

        for segment in segments {
            let url = directory.appendingPathComponent(segment.filename)
            let asset = AVURLAsset(url: url)

            do {
                guard let srcVideo = asset.tracks(withMediaType: .video).first else { continue }
                let timeRange = srcVideo.timeRange
                guard timeRange.duration > .zero else { continue }

                try videoTrack.insertTimeRange(timeRange, of: srcVideo, at: currentTime)

                let audioTracks = asset.tracks(withMediaType: .audio)
                for (index, srcAudio) in audioTracks.enumerated() {
                    while compositionAudioTracks.count <= index {
                        guard let newTrack = composition.addMutableTrack(
                            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
                        ) else { continue }
                        compositionAudioTracks.append(newTrack)
                    }
                    try compositionAudioTracks[index].insertTimeRange(timeRange, of: srcAudio, at: currentTime)
                }

                currentTime = CMTimeAdd(currentTime, timeRange.duration)
            } catch {
                print("[CompositionBuilder] Failed to insert segment: \(error)")
            }
        }

        return currentTime > .zero ? composition : nil
    }
}

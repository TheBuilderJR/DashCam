import Foundation

final class SnapshotManager: ObservableObject {
    static let snapshotsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dashcam/snapshots", isDirectory: true)
    }()

    @Published var snapshots: [Snapshot] = []

    private let fm = FileManager.default

    init() {
        try? fm.createDirectory(at: Self.snapshotsDirectory, withIntermediateDirectories: true)
        loadSnapshots()
    }

    func createSnapshot(from ringBuffer: RingBufferManager, maxDuration: TimeInterval) -> Snapshot? {
        let allSegments = ringBuffer.flushAndGetSegments()
        let nonEmpty = allSegments.filter { $0.duration > 0 }
        guard !nonEmpty.isEmpty else {
            print("[SnapshotManager] No segments with content to snapshot")
            return nil
        }

        // Keep only the most recent segments that fit within maxDuration
        let sorted = nonEmpty.sorted { $0.startTime > $1.startTime }
        var accumulated: TimeInterval = 0
        var selected: [SegmentInfo] = []
        for segment in sorted {
            if accumulated >= maxDuration { break }
            selected.append(segment)
            accumulated += segment.duration
        }
        let segments = Array(selected.reversed()) // restore chronological order

        let snapshotID = UUID()
        let snapshotDir = Self.snapshotsDirectory.appendingPathComponent(snapshotID.uuidString)

        do {
            try fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

            // Copy segments and sidecars (APFS clone if available)
            for segment in segments {
                let srcMov = RingBufferManager.bufferDirectory.appendingPathComponent(segment.filename)
                let dstMov = snapshotDir.appendingPathComponent(segment.filename)
                try fm.copyItem(at: srcMov, to: dstMov)

                let srcJSON = RingBufferManager.bufferDirectory.appendingPathComponent(segment.sidecarFilename)
                let dstJSON = snapshotDir.appendingPathComponent(segment.sidecarFilename)
                if fm.fileExists(atPath: srcJSON.path) {
                    try fm.copyItem(at: srcJSON, to: dstJSON)
                }
            }

            // Remove ALL flushed segments from buffer (not just selected ones)
            // so older-than-maxDuration segments don't reappear in future snapshots
            for segment in allSegments {
                let srcMov = RingBufferManager.bufferDirectory.appendingPathComponent(segment.filename)
                let srcJSON = RingBufferManager.bufferDirectory.appendingPathComponent(segment.sidecarFilename)
                try? fm.removeItem(at: srcMov)
                try? fm.removeItem(at: srcJSON)
            }

            let snapshot = Snapshot(id: snapshotID, createdAt: Date(), segments: segments)

            // Write manifest
            let manifest = SnapshotManifest(
                snapshotID: snapshotID,
                createdAt: snapshot.createdAt,
                segments: segments,
                totalDuration: snapshot.totalDuration
            )
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: snapshotDir.appendingPathComponent("manifest.json"))

            DispatchQueue.main.async {
                self.snapshots.insert(snapshot, at: 0)
            }
            print("[SnapshotManager] Created snapshot \(snapshotID)")
            return snapshot
        } catch {
            print("[SnapshotManager] Failed to create snapshot: \(error)")
            try? fm.removeItem(at: snapshotDir)
            return nil
        }
    }

    func deleteSnapshot(_ snapshot: Snapshot) {
        let dir = Self.snapshotsDirectory.appendingPathComponent(snapshot.id.uuidString)
        try? fm.removeItem(at: dir)
        DispatchQueue.main.async {
            self.snapshots.removeAll { $0.id == snapshot.id }
        }
        print("[SnapshotManager] Deleted snapshot \(snapshot.id)")
    }

    private func loadSnapshots() {
        guard let dirs = try? fm.contentsOfDirectory(at: Self.snapshotsDirectory, includingPropertiesForKeys: [.creationDateKey])
        else { return }

        var loaded: [Snapshot] = []
        for dir in dirs {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(SnapshotManifest.self, from: data)
            else { continue }
            let snapshot = Snapshot(
                id: manifest.snapshotID,
                createdAt: manifest.createdAt,
                segments: manifest.segments
            )
            loaded.append(snapshot)
        }

        snapshots = loaded.sorted { $0.createdAt > $1.createdAt }
    }
}

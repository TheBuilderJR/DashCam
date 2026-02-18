import Foundation

struct Snapshot: Codable, Identifiable, Hashable {
    static func == (lhs: Snapshot, rhs: Snapshot) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    let createdAt: Date
    var segments: [SegmentInfo]
    var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    var directory: URL {
        SnapshotManager.snapshotsDirectory.appendingPathComponent(id.uuidString)
    }
}

struct SegmentInfo: Codable, Identifiable {
    let id: UUID
    let filename: String
    let sidecarFilename: String
    let startTime: Date
    let duration: TimeInterval
}

struct SegmentSidecar: Codable {
    let segmentID: UUID
    let startTime: Date
    let endTime: Date
    var clipboardEvents: [ClipboardEvent]
}

struct SnapshotManifest: Codable {
    let snapshotID: UUID
    let createdAt: Date
    let segments: [SegmentInfo]
    let totalDuration: TimeInterval
}

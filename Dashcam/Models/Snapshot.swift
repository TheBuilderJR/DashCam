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
    var keystrokeEvents: [KeystrokeEvent]

    init(segmentID: UUID, startTime: Date, endTime: Date, clipboardEvents: [ClipboardEvent], keystrokeEvents: [KeystrokeEvent] = []) {
        self.segmentID = segmentID
        self.startTime = startTime
        self.endTime = endTime
        self.clipboardEvents = clipboardEvents
        self.keystrokeEvents = keystrokeEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        segmentID = try container.decode(UUID.self, forKey: .segmentID)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        clipboardEvents = try container.decode([ClipboardEvent].self, forKey: .clipboardEvents)
        keystrokeEvents = try container.decodeIfPresent([KeystrokeEvent].self, forKey: .keystrokeEvents) ?? []
    }
}

struct SnapshotManifest: Codable {
    let snapshotID: UUID
    let createdAt: Date
    let segments: [SegmentInfo]
    let totalDuration: TimeInterval
}

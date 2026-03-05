import AVFoundation
import AVKit
import SwiftUI

struct LiveBufferDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var player: AVPlayer?
    @State private var playerReady = false
    @State private var isLoading = false
    @State private var segments: [SegmentInfo] = []
    @State private var saveMessage: String?
    @State private var clipboardEvents: [ClipboardEvent] = []
    @State private var keystrokeEvents: [KeystrokeEvent] = []

    var body: some View {
        VStack(spacing: 0) {
            // Video player
            if let player, playerReady {
                PlayerViewRepresentable(player: player)
                    .frame(minHeight: 300)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(minHeight: 300)
                    .overlay {
                        if isLoading {
                            ProgressView("Loading buffer...")
                                .foregroundStyle(.white)
                        } else {
                            Text("No buffer content")
                                .foregroundStyle(.white)
                        }
                    }
            }

            // Info and controls
            HStack {
                VStack(alignment: .leading) {
                    Text("Segments: \(segments.count)")
                    Text("Duration: \(formattedDuration(totalDuration))")
                    if let first = segments.first, let last = segments.last {
                        Text("Range: \(first.startTime.formatted(date: .omitted, time: .standard)) – \(last.startTime.addingTimeInterval(last.duration).formatted(date: .omitted, time: .standard))")
                    }
                }
                .font(.caption)

                Spacer()

                Button("Refresh") {
                    loadBuffer()
                }

                Button("Save as Snapshot") {
                    saveAsSnapshot()
                }
                .disabled(segments.isEmpty)

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            // Clipboard events
            if !clipboardEvents.isEmpty {
                Divider()

                Text("Clipboard (\(clipboardEvents.count))")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                List(clipboardEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(event.content)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
                .frame(minHeight: 120)
            }

            // Keystroke events
            if !keystrokeGroups.isEmpty {
                Divider()

                Text("Keystrokes (\(keystrokeEvents.count))")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                List(keystrokeGroups, id: \.timestamp) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(group.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(minHeight: 120)
            }
        }
        .onAppear {
            loadBuffer()
        }
        .onDisappear {
            player?.pause()
            player = nil
            playerReady = false
        }
    }

    private var keystrokeGroups: [SnapshotDetailView.KeystrokeGroup] {
        SnapshotDetailView.groupKeystrokes(keystrokeEvents)
    }

    private var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    private func loadBuffer() {
        isLoading = true
        playerReady = false
        player?.pause()
        player = nil

        Task.detached { [appState] in
            let segs = appState.ringBufferManager.flushAndResume()
            let composition = CompositionBuilder.buildComposition(
                segments: segs,
                directory: RingBufferManager.bufferDirectory
            )

            // Load sidecar data from buffer segments
            var allClipboard: [ClipboardEvent] = []
            var allKeystrokes: [KeystrokeEvent] = []
            for segment in segs {
                let sidecarURL = RingBufferManager.bufferDirectory.appendingPathComponent(segment.sidecarFilename)
                guard let data = try? Data(contentsOf: sidecarURL),
                      let sidecar = try? JSONDecoder().decode(SegmentSidecar.self, from: data)
                else { continue }
                allClipboard.append(contentsOf: sidecar.clipboardEvents)
                allKeystrokes.append(contentsOf: sidecar.keystrokeEvents)
            }

            await MainActor.run {
                segments = segs
                clipboardEvents = allClipboard.sorted { $0.timestamp < $1.timestamp }
                keystrokeEvents = allKeystrokes.sorted { $0.timestamp < $1.timestamp }
                if let composition {
                    let avPlayer = AVPlayer(playerItem: AVPlayerItem(asset: composition))
                    player = avPlayer
                    playerReady = true
                    avPlayer.play()
                } else {
                    playerReady = true // stop showing loading
                }
                isLoading = false
            }
        }
    }

    private func saveAsSnapshot() {
        let segs = segments
        guard !segs.isEmpty else { return }
        Task.detached { [appState] in
            let snapshot = appState.snapshotManager.createSnapshotFromBufferSegments(segs)
            await MainActor.run {
                if snapshot != nil {
                    saveMessage = "Snapshot saved"
                } else {
                    saveMessage = "Save failed"
                }
            }
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m \(seconds)s"
    }
}

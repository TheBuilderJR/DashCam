import AVFoundation
import AVKit
import SwiftUI

struct PlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct SnapshotDetailView: View {
    let snapshot: Snapshot
    @EnvironmentObject var appState: AppState
    @State private var player: AVPlayer?
    @State private var playerReady = false
    @State private var exportMessage: String?
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
                        if snapshot.segments.isEmpty || playerReady {
                            Text("No video content")
                                .foregroundStyle(.white)
                        } else {
                            ProgressView("Loading...")
                                .foregroundStyle(.white)
                        }
                    }
            }

            // Controls
            HStack {
                VStack(alignment: .leading) {
                    Text("Created: \(snapshot.createdAt.formatted())")
                    Text("Duration: \(formattedDuration(snapshot.totalDuration))")
                    Text("Segments: \(snapshot.segments.count)")
                }
                .font(.caption)

                Spacer()

                if appState.videoExporter.isExporting {
                    ProgressView(value: appState.videoExporter.progress)
                        .frame(width: 100)
                    Text("\(Int(appState.videoExporter.progress * 100))%")
                        .font(.caption)
                } else {
                    Button("Export as MP4") {
                        exportSnapshot()
                    }
                    .disabled(snapshot.segments.isEmpty)
                }

                if let exportMessage {
                    Text(exportMessage)
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
            setupPlayer()
            loadSidecarData()
        }
        .onDisappear {
            player?.pause()
            player = nil
            playerReady = false
        }
    }

    struct KeystrokeGroup: Hashable {
        let timestamp: Date
        let text: String
    }

    private var keystrokeGroups: [KeystrokeGroup] {
        Self.groupKeystrokes(keystrokeEvents)
    }

    static func groupKeystrokes(_ events: [KeystrokeEvent], debounceInterval: TimeInterval = 60) -> [KeystrokeGroup] {
        guard !events.isEmpty else { return [] }
        var groups: [(timestamp: Date, chars: String)] = []
        var lastTimestamp: Date? = nil
        for event in events {
            guard let typed = event.typedCharacter else { continue }
            if let last = lastTimestamp,
               event.timestamp.timeIntervalSince(last) > debounceInterval {
                groups.append((timestamp: event.timestamp, chars: typed))
            } else if groups.isEmpty {
                groups.append((timestamp: event.timestamp, chars: typed))
            } else {
                groups[groups.count - 1].chars.append(typed)
            }
            lastTimestamp = event.timestamp
        }
        return groups
            .map { KeystrokeGroup(timestamp: $0.timestamp, text: $0.chars.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
    }

    private func loadSidecarData() {
        var allClipboard: [ClipboardEvent] = []
        var allKeystrokes: [KeystrokeEvent] = []
        for segment in snapshot.segments {
            let sidecarURL = snapshot.directory.appendingPathComponent(segment.sidecarFilename)
            guard let data = try? Data(contentsOf: sidecarURL),
                  let sidecar = try? JSONDecoder().decode(SegmentSidecar.self, from: data)
            else { continue }
            allClipboard.append(contentsOf: sidecar.clipboardEvents)
            allKeystrokes.append(contentsOf: sidecar.keystrokeEvents)
        }
        clipboardEvents = allClipboard.sorted { $0.timestamp < $1.timestamp }
        keystrokeEvents = allKeystrokes.sorted { $0.timestamp < $1.timestamp }
    }

    private func setupPlayer() {
        guard let composition = CompositionBuilder.buildComposition(
            segments: snapshot.segments,
            directory: snapshot.directory
        ) else {
            playerReady = true
            return
        }
        let avPlayer = AVPlayer(playerItem: AVPlayerItem(asset: composition))
        self.player = avPlayer
        self.playerReady = true
        avPlayer.play()
    }

    private func exportSnapshot() {
        appState.videoExporter.export(snapshot: snapshot) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    exportMessage = "Exported to \(url.lastPathComponent)"
                case .failure(let error):
                    if case VideoExporter.ExportError.cancelled = error {
                        exportMessage = nil
                    } else {
                        exportMessage = "Export failed: \(error.localizedDescription)"
                    }
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

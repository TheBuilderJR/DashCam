import SwiftUI

struct SnapshotListView: View {
    @EnvironmentObject var appState: AppState

    enum SidebarSelection: Hashable {
        case liveBuffer
        case snapshot(UUID)
    }

    @State private var selection: SidebarSelection?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if appState.isRecording {
                    Label("Live Buffer", systemImage: "record.circle")
                        .tag(SidebarSelection.liveBuffer)
                        .foregroundStyle(.red)
                }

                Section("Snapshots") {
                    ForEach(appState.snapshotManager.snapshots, id: \.id) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.createdAt, style: .date)
                                .font(.headline)
                            Text(snapshot.createdAt, style: .time)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(snapshot.segments.count) segments - \(formattedDuration(snapshot.totalDuration))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .tag(SidebarSelection.snapshot(snapshot.id))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                appState.snapshotManager.deleteSnapshot(snapshot)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Snapshots")
        } detail: {
            switch selection {
            case .liveBuffer:
                LiveBufferDetailView()
                    .environmentObject(appState)
            case .snapshot(let id):
                if let snapshot = appState.snapshotManager.snapshots.first(where: { $0.id == id }) {
                    SnapshotDetailView(snapshot: snapshot)
                        .environmentObject(appState)
                        .id(snapshot.id)
                } else {
                    Text("Select a snapshot to view")
                        .foregroundStyle(.secondary)
                }
            case nil:
                Text("Select a snapshot to view")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
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

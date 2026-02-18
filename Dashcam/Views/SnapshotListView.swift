import SwiftUI

struct SnapshotListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSnapshotID: UUID?

    var body: some View {
        NavigationSplitView {
            List(appState.snapshotManager.snapshots, id: \.id, selection: $selectedSnapshotID) { snapshot in
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
                .tag(snapshot.id)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        appState.snapshotManager.deleteSnapshot(snapshot)
                    }
                }
            }
            .navigationTitle("Snapshots")
        } detail: {
            if let id = selectedSnapshotID,
               let snapshot = appState.snapshotManager.snapshots.first(where: { $0.id == id }) {
                SnapshotDetailView(snapshot: snapshot)
                    .environmentObject(appState)
                    .id(snapshot.id)
            } else {
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

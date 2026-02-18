import Foundation

struct ClipboardEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let content: String

    init(content: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.content = String(content.prefix(1000))
    }
}

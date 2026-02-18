import AppKit
import Foundation

final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    var onClipboardChange: ((ClipboardEvent) -> Void)?

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        print("[ClipboardMonitor] Started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        print("[ClipboardMonitor] Stopped")
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let content = pasteboard.string(forType: .string), !content.isEmpty else { return }
        let event = ClipboardEvent(content: content)
        print("[ClipboardMonitor] Captured: \(content.prefix(50))...")
        onClipboardChange?(event)
    }
}

import Cocoa
import Foundation

final class KeystrokeMonitor {
    var onKeystroke: ((KeystrokeEvent) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard KeystrokeMonitor.isAccessibilityGranted else {
            print("[KeystrokeMonitor] Accessibility not granted")
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

        print("[KeystrokeMonitor] Started")
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        print("[KeystrokeMonitor] Stopped")
    }

    private func handleEvent(_ event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? event.characters ?? ""
        let modifierFlags = event.modifierFlags.rawValue
        let keystrokeEvent = KeystrokeEvent(
            keyCode: event.keyCode,
            characters: chars,
            modifiers: modifierFlags
        )
        print("[KeystrokeMonitor] Key: \(keystrokeEvent.displayString) (code=\(event.keyCode))")
        onKeystroke?(keystrokeEvent)
    }
}

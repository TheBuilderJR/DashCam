import Foundation

struct KeystrokeEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let keyCode: UInt16
    let characters: String
    let modifiers: UInt

    init(keyCode: UInt16, characters: String, modifiers: UInt) {
        self.id = UUID()
        self.timestamp = Date()
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
    }

    var displayString: String {
        var parts: [String] = []

        if modifiers & (1 << 18) != 0 { parts.append("⌃") }   // Control
        if modifiers & (1 << 19) != 0 { parts.append("⌥") }   // Option
        if modifiers & (1 << 17) != 0 { parts.append("⇧") }   // Shift
        if modifiers & (1 << 20) != 0 { parts.append("⌘") }   // Command

        let label = Self.specialKeyLabel(keyCode) ?? characters
        parts.append(label)

        return parts.joined()
    }

    /// Returns the typed text character for this keystroke, or nil if it's a non-text key (shortcuts, arrows, function keys, etc.)
    var typedCharacter: String? {
        let hasCommand = modifiers & (1 << 20) != 0
        let hasControl = modifiers & (1 << 18) != 0

        // Skip shortcut combos (⌘ or ⌃ held) — these aren't typed text
        if hasCommand || hasControl { return nil }

        // Return/Enter → newline
        if keyCode == 36 || keyCode == 76 { return "\n" }
        // Tab → tab
        if keyCode == 48 { return "\t" }

        // Skip non-text special keys (arrows, F-keys, escape, delete, etc.)
        let nonTextKeyCodes: Set<UInt16> = [
            51, 53, 117,           // backspace, escape, forward delete
            123, 124, 125, 126,    // arrows
            115, 119, 116, 121,    // home, end, page up, page down
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
        ]
        if nonTextKeyCodes.contains(keyCode) { return nil }

        // Regular character
        return characters.isEmpty ? nil : characters
    }

    private static func specialKeyLabel(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "⏎"
        case 48: return "⇥"
        case 49: return "␣"
        case 51: return "⌫"
        case 53: return "⎋"
        case 76: return "⌤"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return nil
        }
    }
}

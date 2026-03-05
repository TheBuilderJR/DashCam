import Cocoa
import SwiftUI

// MARK: - View Model

final class KeystrokeOverlayViewModel: ObservableObject {
    struct VisibleKey: Identifiable {
        let id: UUID
        let displayString: String
    }

    @Published var visibleKeys: [VisibleKey] = []

    private let fadeDelay: TimeInterval = 2.0

    func addKeystroke(_ event: KeystrokeEvent) {
        let key = VisibleKey(id: event.id, displayString: event.displayString)
        DispatchQueue.main.async {
            withAnimation(.easeIn(duration: 0.15)) {
                self.visibleKeys.append(key)
            }
            // Keep at most 10 visible
            if self.visibleKeys.count > 10 {
                self.visibleKeys.removeFirst(self.visibleKeys.count - 10)
            }
        }
        let keyID = key.id
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) {
            withAnimation(.easeOut(duration: 0.3)) {
                self.visibleKeys.removeAll { $0.id == keyID }
            }
        }
    }

    func clear() {
        visibleKeys.removeAll()
    }
}

// MARK: - SwiftUI View

struct KeystrokeOverlayView: View {
    @ObservedObject var viewModel: KeystrokeOverlayViewModel

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 4) {
                ForEach(viewModel.visibleKeys) { key in
                    Text(key.displayString)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.7))
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Overlay Window

final class KeystrokeOverlayWindow {
    let viewModel = KeystrokeOverlayViewModel()
    private var window: NSWindow?

    func show() {
        guard window == nil else { return }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let hostingView = NSHostingView(rootView: KeystrokeOverlayView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: screenFrame.width, height: 80)

        let panel = NSPanel(
            contentRect: NSRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.window = panel
        print("[KeystrokeOverlay] Window shown at \(panel.frame)")
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        viewModel.clear()
    }

    func addKeystroke(_ event: KeystrokeEvent) {
        print("[KeystrokeOverlay] Adding keystroke: \(event.displayString), window visible: \(window != nil)")
        viewModel.addKeystroke(event)
    }
}

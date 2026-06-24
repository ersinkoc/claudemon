import AppKit
import SwiftUI

/// Manages a borderless, always-on-top, non-activating NSPanel hosting the
/// compact SwiftUI widget. The panel is draggable by its background and does
/// not steal focus from the active app.
@MainActor
final class FloatingPanelController {

    private var panel: NSPanel?
    private let store: UsageStore
    private static let frameAutosaveName = "ClaudemonFloatingPanel"

    init(store: UsageStore) {
        self.store = store
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        // orderFrontRegardless avoids activating the app (no focus steal).
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let contentSize = NSSize(width: 210, height: 112)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hosting = NSHostingView(rootView: FloatingWidgetView(store: store))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Restore prior position, or place near top-right of the main screen.
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        if panel.frame.origin == .zero {
            positionDefault(panel)
        }

        return panel
    }

    private func positionDefault(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - 24
        let y = visible.maxY - panel.frame.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

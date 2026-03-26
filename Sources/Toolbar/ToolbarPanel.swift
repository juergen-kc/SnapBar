import AppKit
import SwiftUI

/// A borderless, floating NSPanel that hosts the SnapBar toolbar.
/// Stays above all windows, doesn't steal focus, and dismisses on outside interaction.
final class ToolbarPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // Liquid Glass provides its own shadow/depth
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow

        // Don't show in Mission Control or App Exposé
        isExcludedFromWindowsMenu = true
    }

    // Allow the panel to become key only when a button is clicked
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Dismiss when clicking outside
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

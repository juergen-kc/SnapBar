import AppKit

/// A borderless, floating NSPanel that hosts the SnapBar toolbar.
/// Stays above all windows, doesn't steal focus, and dismisses on outside interaction.
final class ToolbarPanel: NSPanel {
    /// The visible toolbar height (excluding tooltip padding at the bottom).
    /// Set by ToolbarController after sizing. Used for hit-testing.
    var visibleContentHeight: CGFloat = 0

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
        hasShadow = false  // shadow is applied in ToolbarView, gated on reduceTransparency
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow

        // Don't show in Mission Control or App Exposé
        isExcludedFromWindowsMenu = true

        // Required for reliable hover tracking in SwiftUI on non-activating panels
        acceptsMouseMovedEvents = true
    }

    // Allow the panel to become key only when a button is clicked
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Whether a screen-coordinate point is inside the visible toolbar area (excluding tooltip padding).
    func isPointInVisibleToolbar(_ screenPoint: CGPoint) -> Bool {
        let framePoint = CGPoint(x: screenPoint.x - frame.minX, y: screenPoint.y - frame.minY)
        // Visible toolbar is in the upper portion; bottom padding is for tooltip overflow
        let tooltipPadding = frame.height - visibleContentHeight
        let visibleRect = CGRect(x: 0, y: tooltipPadding, width: frame.width, height: visibleContentHeight)
        return visibleRect.contains(framePoint)
    }
}

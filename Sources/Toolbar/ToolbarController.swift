import AppKit
import SwiftUI

/// Manages showing, hiding, and positioning the floating toolbar.
@MainActor
final class ToolbarController {
    private let appState: AppState
    private var panel: ToolbarPanel?
    private var dismissMonitor: Any?
    private var scrollMonitor: Any?
    private var keyboardShortcutMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        installKeyboardShortcut()
    }

    /// Call before releasing to clean up event monitors
    func tearDown() {
        removeDismissMonitors()
        removeMonitor(&keyboardShortcutMonitor)
    }

    // MARK: - Show / Dismiss

    func show(for selection: TextSelection, keyboardMode: Bool = false) {
        let actions = ActionRegistry.applicableActions(for: selection, config: appState.enabledActions)
        guard !actions.isEmpty else { return }

        dismiss()

        appState.currentSelection = selection
        appState.isToolbarVisible = true

        let panel = ToolbarPanel()
        self.panel = panel

        let toolbarView = ToolbarView(
            actions: actions,
            selection: selection,
            onDismiss: { [weak self] in self?.dismiss() },
            keyboardMode: keyboardMode
        )
        .environment(appState)

        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.frame.size = hostingView.fittingSize
        panel.contentView = hostingView
        panel.setContentSize(hostingView.fittingSize)

        let toolbarFrame = calculatePosition(
            selectionBounds: selection.bounds,
            toolbarSize: hostingView.fittingSize,
            position: appState.toolbarPosition
        )
        panel.setFrameOrigin(toolbarFrame.origin)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        if keyboardMode {
            panel.makeKey()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }

        installDismissMonitors()
    }

    /// Show toolbar for long-press (no text selected — shows paste-only actions at cursor location)
    func showForLongPress(at point: CGPoint) {
        let isEditable = AccessibilityHelper.isEditable()
        let text = AccessibilityHelper.selectedText() ?? ""

        let selection = TextSelection(
            text: text,
            bounds: CGRect(origin: point, size: .zero),
            isEditable: isEditable
        )

        show(for: selection)
    }

    /// Summon toolbar via keyboard shortcut on current selection
    func summonViaKeyboard() {
        guard let text = AccessibilityHelper.selectedText(), !text.isEmpty else { return }

        let bounds = AccessibilityHelper.selectedTextBounds()
            ?? CGRect(origin: AccessibilityHelper.axPoint(from: NSEvent.mouseLocation), size: .zero)

        let selection = TextSelection(
            text: text,
            bounds: bounds,
            isEditable: AccessibilityHelper.isEditable()
        )

        show(for: selection, keyboardMode: true)
    }

    func dismiss() {
        guard let panel else { return }

        appState.isToolbarVisible = false
        appState.currentSelection = nil

        removeDismissMonitors()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        })
    }

    // MARK: - Keyboard Shortcut

    private func installKeyboardShortcut() {
        // Global shortcut: ⌃⌥S to summon toolbar in keyboard mode
        keyboardShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Control + Option + S
            let requiredFlags: NSEvent.ModifierFlags = [.control, .option]
            guard event.modifierFlags.contains(requiredFlags),
                  event.charactersIgnoringModifiers == "s" else { return }

            Task { @MainActor in
                self?.summonViaKeyboard()
            }
        }
    }

    // MARK: - Positioning

    private func calculatePosition(selectionBounds: CGRect, toolbarSize: CGSize, position: ToolbarPosition) -> CGRect {
        // Find the screen containing the selection point
        let screen = screenContaining(axPoint: selectionBounds.origin) ?? NSScreen.main ?? NSScreen.screens.first

        guard let screen else {
            return CGRect(origin: selectionBounds.origin, size: toolbarSize)
        }

        let screenFrame = screen.visibleFrame
        let gap: CGFloat = 8

        // Convert AX coordinates (top-left origin) to AppKit screen coordinates (bottom-left origin)
        let selectionScreenY = screen.frame.origin.y + screen.frame.height - selectionBounds.origin.y

        var x = selectionBounds.origin.x + (selectionBounds.width - toolbarSize.width) / 2
        var y: CGFloat

        switch position {
        case .above:
            y = selectionScreenY + gap
        case .below:
            y = selectionScreenY - selectionBounds.height - toolbarSize.height - gap
        }

        x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - toolbarSize.width - 4))
        y = max(screenFrame.minY + 4, min(y, screenFrame.maxY - toolbarSize.height - 4))

        return CGRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
    }

    /// Find the screen that contains a point in AX coordinate space (top-left origin)
    private func screenContaining(axPoint: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            let frame = screen.frame
            // Convert AX Y to AppKit Y for this screen
            let appKitY = frame.origin.y + frame.height - axPoint.y
            let appKitPoint = NSPoint(x: axPoint.x, y: appKitY)
            if frame.contains(appKitPoint) {
                return screen
            }
        }
        return nil
    }

    // MARK: - Dismiss Monitors

    private func installDismissMonitors() {
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return }
            let locationInPanel = panel.convertPoint(fromScreen: event.locationInWindow)
            if let contentView = panel.contentView, !contentView.bounds.contains(locationInPanel) {
                self.dismiss()
            }
        }

        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeDismissMonitors() {
        removeMonitor(&dismissMonitor)
        removeMonitor(&scrollMonitor)
    }

    private func removeMonitor(_ monitor: inout Any?) {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

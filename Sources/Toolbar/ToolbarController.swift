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
        let fittingSize = hostingView.fittingSize
        panel.contentView = hostingView
        panel.setContentSize(fittingSize)

        panel.setFrameOrigin(calculatePosition(
            selectionBounds: selection.bounds,
            toolbarSize: fittingSize,
            position: appState.toolbarPosition
        ).origin)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        if keyboardMode {
            panel.makeKey()
        }

        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.1
            panel.animator().alphaValue = 1
        }

        installDismissMonitors()
    }

    /// Show toolbar for long-press (no text selected — shows paste-only actions at cursor location)
    func showForLongPress(at point: CGPoint) {
        show(for: TextSelection(
            text: AccessibilityHelper.selectedText() ?? "",
            bounds: CGRect(origin: point, size: .zero),
            isEditable: AccessibilityHelper.isEditable()
        ))
    }

    /// Summon toolbar via keyboard shortcut on current selection
    func summonViaKeyboard() {
        guard let text = AccessibilityHelper.selectedText(), !text.isEmpty else { return }
        show(for: TextSelection(
            text: text,
            bounds: AccessibilityHelper.selectedTextBoundsOrMouse(),
            isEditable: AccessibilityHelper.isEditable()
        ), keyboardMode: true)
    }

    func dismiss() {
        guard let panel else { return }

        appState.isToolbarVisible = false
        appState.currentSelection = nil

        removeDismissMonitors()

        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.08
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        }
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
        guard let screen = screenContaining(axPoint: selectionBounds.origin) ?? NSScreen.main ?? NSScreen.screens.first else {
            return CGRect(origin: selectionBounds.origin, size: toolbarSize)
        }

        let screenFrame = screen.visibleFrame
        let gap: CGFloat = 8

        // Convert AX coordinates (top-left origin) to AppKit screen coordinates (bottom-left origin)
        let selectionScreenY = screen.frame.origin.y + screen.frame.height - selectionBounds.origin.y

        var x = selectionBounds.origin.x + (selectionBounds.width - toolbarSize.width) / 2
        var y = switch position {
        case .above: selectionScreenY + gap
        case .below: selectionScreenY - selectionBounds.height - toolbarSize.height - gap
        }

        x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - toolbarSize.width - 4))
        y = max(screenFrame.minY + 4, min(y, screenFrame.maxY - toolbarSize.height - 4))

        return CGRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
    }

    /// Find the screen that contains a point in AX coordinate space (top-left origin)
    private func screenContaining(axPoint: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            let frame = screen.frame
            return frame.contains(NSPoint(x: axPoint.x, y: frame.origin.y + frame.height - axPoint.y))
        }
    }

    // MARK: - Dismiss Monitors

    private func installDismissMonitors() {
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return }
            guard panel.contentView?.bounds.contains(panel.convertPoint(fromScreen: event.locationInWindow)) == true else {
                self.dismiss()
                return
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
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

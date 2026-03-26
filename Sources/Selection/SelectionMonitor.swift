import AppKit
import ApplicationServices

/// Monitors for text selection using Accessibility polling.
@MainActor
final class SelectionMonitor: @unchecked Sendable {
    private let appState: AppState
    private let onSelection: @MainActor (TextSelection) -> Void

    private var pollingTimer: Timer?
    private var lastSelectedText: String = ""
    private var lastMouseLocation: CGPoint = .zero

    init(appState: AppState, onSelection: @MainActor @escaping (TextSelection) -> Void) {
        self.appState = appState
        self.onSelection = onSelection
    }

    func start() {
        guard AccessibilityHelper.isTrusted() else { return }

        // Poll at ~5Hz — good balance of responsiveness vs CPU usage
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSelection()
            }
        }

        DebugLog.log("Selection polling started (5Hz)")
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func checkForSelection() {
        // Skip if automatic appearance is disabled
        guard appState.appearAutomatically else { return }

        // Track mouse position
        let currentMouse = NSEvent.mouseLocation
        let mouseButtons = NSEvent.pressedMouseButtons
        let isMouseDown = (mouseButtons & 1) != 0

        // Only check when mouse button is NOT pressed (selection just completed)
        guard !isMouseDown else {
            lastMouseLocation = currentMouse
            return
        }

        // Check if there's selected text
        guard let text = AccessibilityHelper.selectedText(), !text.isEmpty else {
            lastSelectedText = ""
            return
        }

        // Only trigger if the selection changed
        guard text != lastSelectedText else { return }
        lastSelectedText = text

        // Skip whitespace-only selections
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Guard against extremely large selections
        let cappedText = text.count > 10_000 ? String(text.prefix(10_000)) : text

        DebugLog.log("Selection detected: '\(cappedText.prefix(40))'")

        // Get bounds and context — use screen-aware mouse fallback
        let mouseAXPoint: CGPoint = {
            let screenHeight = NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 900
            return CGPoint(x: currentMouse.x, y: screenHeight - currentMouse.y)
        }()

        let bounds = AccessibilityHelper.selectedTextBounds() ?? CGRect(origin: mouseAXPoint, size: .zero)
        let isEditable = AccessibilityHelper.isEditable()
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let selection = TextSelection(
            text: cappedText,
            bounds: bounds,
            isEditable: isEditable,
            bundleIdentifier: bundleID
        )

        onSelection(selection)
    }
}

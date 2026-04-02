import AppKit

/// Monitors for text selection using Accessibility polling.
@MainActor
final class SelectionMonitor: @unchecked Sendable {
    private let appState: AppState
    private let onSelection: @MainActor (TextSelection) -> Void

    private var pollingTimer: Timer?
    private var lastSelectedText = ""
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

        // Only check when mouse button is NOT pressed (selection just completed)
        guard (NSEvent.pressedMouseButtons & 1) == 0 else {
            lastMouseLocation = NSEvent.mouseLocation
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

        let cappedText = String(text.prefix(10_000))
        DebugLog.log("Selection detected: '\(cappedText.prefix(40))'")
        onSelection(TextSelection(
            text: cappedText,
            bounds: AccessibilityHelper.selectedTextBoundsOrMouse(),
            isEditable: AccessibilityHelper.isEditable()
        ))
    }
}

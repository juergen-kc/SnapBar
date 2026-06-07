import AppKit

struct SelectionEmissionState {
    private var lastSelectedText = ""

    mutating func textToEmit(from text: String?) -> String? {
        guard let text, !text.isEmpty,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastSelectedText = ""
            return nil
        }

        guard text != lastSelectedText else { return nil }
        lastSelectedText = text
        return String(text.prefix(10_000))
    }
}

enum ClipboardFallbackPolicy {
    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "com.operasoftware.Opera",
        "company.thebrowser.Browser",
    ]

    static func allowsFallback(for bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map(browserBundleIdentifiers.contains) ?? false
    }
}

/// Monitors for text selection using Accessibility polling + global mouse events.
@MainActor
final class SelectionMonitor: @unchecked Sendable {
    private let appState: AppState
    private let onSelection: @MainActor (TextSelection) -> Void

    private var pollingTimer: Timer?
    private var mouseUpMonitor: Any?
    private var selectionEmissionState = SelectionEmissionState()

    init(appState: AppState, onSelection: @MainActor @escaping (TextSelection) -> Void) {
        self.appState = appState
        self.onSelection = onSelection
    }

    func start() {
        guard AccessibilityHelper.isTrusted() else { return }

        // Poll at ~5Hz for AX-based selection (native apps like Terminal, TextEdit, etc.)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkViaAX()
            }
        }

        // Global mouse-up monitor triggers clipboard fallback for browsers.
        // Unlike polling pressedMouseButtons, this never misses a mouse release.
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            let mousePos = NSEvent.mouseLocation  // capture at mouse-up time
            Task { @MainActor in
                // Brief delay for the app to finalize the selection
                try? await Task.sleep(for: .milliseconds(100))
                self?.checkViaClipboard(mousePosition: mousePos)
            }
        }

        DebugLog.log("Selection polling started (5Hz)")
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        mouseUpMonitor = nil
    }

    /// Fast path: read selected text via Accessibility API (works for native apps).
    private func checkViaAX() {
        guard appState.appearAutomatically else { return }
        guard (NSEvent.pressedMouseButtons & 1) == 0 else { return }

        guard let text = selectionEmissionState.textToEmit(from: AccessibilityHelper.selectedTextViaAX()) else { return }

        emit(text, bounds: AccessibilityHelper.selectedTextBoundsOrMouse())
    }

    /// Slow path: simulate Cmd+C for browsers that don't expose AXSelectedText (Safari, Chrome on macOS 26+).
    /// Only called once per mouse-up, not at polling frequency.
    private func checkViaClipboard(mousePosition: CGPoint) {
        guard appState.appearAutomatically else { return }

        // Skip if AX can read the selection (native app) — no need for clipboard hack
        if let axText = AccessibilityHelper.selectedTextViaAX(), !axText.isEmpty { return }

        guard ClipboardFallbackPolicy.allowsFallback(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else {
            _ = selectionEmissionState.textToEmit(from: nil)
            return
        }

        guard let text = selectionEmissionState.textToEmit(from: AccessibilityHelper.selectedTextViaClipboard()) else { return }

        let bounds = CGRect(origin: AccessibilityHelper.axPoint(from: mousePosition), size: .zero)
        emit(text, bounds: bounds)
    }

    private func emit(_ text: String, bounds: CGRect) {
        DebugLog.log("Selection detected: '\(text.prefix(40))'")
        onSelection(TextSelection(
            text: text,
            bounds: bounds,
            isEditable: AccessibilityHelper.isEditable()
        ))
    }
}

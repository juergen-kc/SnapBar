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

/// Monitors for text selection using AX notifications (fast path) and polling (1Hz fallback).
@MainActor
final class SelectionMonitor: @unchecked Sendable {
    private let appState: AppState
    private let onSelection: @MainActor (TextSelection) -> Void

    private var pollingTimer: Timer?
    private var mouseUpMonitor: Any?
    private var selectionEmissionState = SelectionEmissionState()

    // AX observer — instant notification when selected text changes in the focused element
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var appActivationObserver: NSObjectProtocol?

    init(appState: AppState, onSelection: @MainActor @escaping (TextSelection) -> Void) {
        self.appState = appState
        self.onSelection = onSelection
    }

    func start() {
        guard AccessibilityHelper.isTrusted() else { return }

        // Fast path: AX notifications fire immediately when text is selected in apps that support them
        startAXObserver()

        // Fallback: 1Hz poll catches apps that don't post kAXSelectedTextChangedNotification
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkViaAX()
            }
        }

        // Mouse-up monitor triggers clipboard fallback for browsers (Safari, Chrome on macOS 26+)
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            let mousePos = NSEvent.mouseLocation
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                self?.checkViaClipboard(mousePosition: mousePos)
            }
        }

        DebugLog.log("Selection monitoring started (AX notifications + 1Hz polling fallback)")
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        mouseUpMonitor = nil
        stopAXObserver()
    }

    // MARK: - AX Observer

    private func startAXObserver() {
        if let app = NSWorkspace.shared.frontmostApplication {
            installAXObserver(for: app.processIdentifier)
        }

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.installAXObserver(for: app.processIdentifier)
            }
        }
    }

    private func stopAXObserver() {
        removeCurrentAXObserver()
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        appActivationObserver = nil
    }

    private func installAXObserver(for pid: pid_t) {
        guard pid != observedPID else { return }
        removeCurrentAXObserver()

        var observer: AXObserver?
        guard AXObserverCreate(pid, axNotificationCallback, &observer) == .success,
              let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()

        // Watch the app element for focus changes so we can re-subscribe to the new focused element
        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, context)

        // Some apps post kAXSelectedTextChangedNotification on the app element
        AXObserverAddNotification(observer, appElement, kAXSelectedTextChangedNotification as CFString, context)

        // Subscribe to the currently focused element (most apps post at this level)
        if let focused = AccessibilityHelper.focusedElement() {
            AXObserverAddNotification(observer, focused, kAXSelectedTextChangedNotification as CFString, context)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        observedPID = pid
    }

    private func removeCurrentAXObserver() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = nil
        observedPID = 0
    }

    /// Called from the file-scope AX callback when any registered notification fires.
    fileprivate func handleAXNotification(_ notification: String) {
        if notification == kAXFocusedUIElementChangedNotification as String {
            // Subscribe to text-change notifications on the newly focused element
            if let observer = axObserver, let focused = AccessibilityHelper.focusedElement() {
                let context = Unmanaged.passUnretained(self).toOpaque()
                AXObserverAddNotification(observer, focused, kAXSelectedTextChangedNotification as CFString, context)
            }
        }
        checkViaAX()
    }

    // MARK: - Selection reading

    /// Fast path: read selected text via Accessibility API (works for native apps).
    private func checkViaAX() {
        guard appState.appearAutomatically else { return }
        guard (NSEvent.pressedMouseButtons & 1) == 0 else { return }

        guard let text = selectionEmissionState.textToEmit(from: AccessibilityHelper.selectedTextViaAX()) else { return }
        emit(text, bounds: AccessibilityHelper.selectedTextBoundsOrMouse())
    }

    /// Slow path: simulate Cmd+C for browsers that don't expose AXSelectedText.
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

// File-scope C callback — AXObserverCallback cannot capture context; self travels via UnsafeMutableRawPointer.
// Safe: stop() removes this observer from the run loop before SelectionMonitor can be deallocated.
private let axNotificationCallback: AXObserverCallback = { _, _, notification, context in
    guard let context else { return }
    let monitor = Unmanaged<SelectionMonitor>.fromOpaque(context).takeUnretainedValue()
    let name = notification as String
    Task { @MainActor in
        monitor.handleAXNotification(name)
    }
}

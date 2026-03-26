import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var selectionMonitor: SelectionMonitor?
    private var toolbarController: ToolbarController?
    private var pluginWatcher: PluginDirectoryWatcher?
    private var accessibilityCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.log("SnapBar launched")

        // Ensure we can receive global events
        NSApp.setActivationPolicy(.accessory)

        toolbarController = ToolbarController(appState: appState)
        selectionMonitor = SelectionMonitor(appState: appState) { [weak self] selection in
            self?.handleSelection(selection)
        }

        StarterPlugins.installIfNeeded()
        ActionRegistry.reloadPlugins()
        DebugLog.log("Loaded \(ActionRegistry.pluginActions.count) plugins")

        pluginWatcher = PluginDirectoryWatcher {
            ActionRegistry.reloadPlugins()
        }

        startMonitoringOrWaitForPermission()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionMonitor?.stop()
        toolbarController?.tearDown()
        accessibilityCheckTimer?.invalidate()
    }

    private func startMonitoringOrWaitForPermission() {
        if AccessibilityHelper.isTrusted() {
            DebugLog.log("Accessibility: GRANTED. Starting monitor.")
            selectionMonitor?.start()
        } else {
            DebugLog.log("Accessibility: NOT GRANTED. Requesting...")
            AccessibilityHelper.requestAccess()

            accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let trusted = AccessibilityHelper.isTrusted()
                    DebugLog.log("Accessibility poll: trusted=\(trusted)")
                    if trusted {
                        DebugLog.log("Accessibility: GRANTED (after wait). Starting monitor.")
                        self.accessibilityCheckTimer?.invalidate()
                        self.accessibilityCheckTimer = nil
                        self.selectionMonitor?.start()
                    }
                }
            }
        }
    }

    @objc private func windowDidClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let visibleWindows = NSApp.windows.filter { $0.isVisible && !($0 is ToolbarPanel) && $0.level == .normal }
            if visibleWindows.isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func handleSelection(_ selection: TextSelection) {
        DebugLog.log("handleSelection: '\(selection.text.prefix(50))' editable=\(selection.isEditable) bounds=\(selection.bounds.debugDescription)")
        guard appState.isEnabled else {
            DebugLog.log("handleSelection: app disabled, ignoring")
            return
        }

        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           appState.excludedApps.contains(bundleID) {
            DebugLog.log("handleSelection: excluded app \(bundleID), ignoring")
            return
        }

        toolbarController?.show(for: selection)
    }
}

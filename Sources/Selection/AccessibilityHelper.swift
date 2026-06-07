import AppKit

struct PasteboardSnapshot {
    private struct Entry {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private let items: [[Entry]]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { Entry(type: type, data: $0) }
            }
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems = items.map { entries in
            let item = NSPasteboardItem()
            for entry in entries {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}

enum AccessibilityHelper {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Read an accessibility attribute, returning nil on failure.
    private static func axAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    /// Get the AXApplication element for the frontmost app.
    private static func frontmostAXApp() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    /// Get the currently focused UI element
    static func focusedElement() -> AXUIElement? {
        guard let axApp = frontmostAXApp() else { return nil }
        // AXUIElement is a CFTypeRef — force cast is required for CF types
        return axAttribute(axApp, kAXFocusedUIElementAttribute as CFString) as! AXUIElement?
    }

    /// Resolve a target element: use the provided element, fall back to focused, then system-wide.
    private static func resolveTarget(_ element: AXUIElement? = nil) -> AXUIElement? {
        element ?? focusedElement()
            ?? axAttribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString) as! AXUIElement?
    }

    /// Try to read kAXSelectedTextAttribute from an element.
    private static func readSelectedText(_ element: AXUIElement) -> String? {
        guard let text = axAttribute(element, kAXSelectedTextAttribute as CFString) as? String,
              !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Clipboard-based selection reading

    /// Simulate Cmd+C to copy selected text, read it from the pasteboard, then restore the previous content.
    /// Used as a fallback for apps (Safari, Chrome) that don't expose AXSelectedText.
    static func selectedTextViaClipboard() -> String? {
        let pb = NSPasteboard.general
        let previousCount = pb.changeCount
        let snapshot = PasteboardSnapshot(pasteboard: pb)

        // Simulate Cmd+C
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else { return nil }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Brief pause for the copy to complete
        usleep(50_000) // 50ms

        // Read the new content
        let newCount = pb.changeCount
        let text: String? = (newCount != previousCount) ? pb.string(forType: .string) : nil

        snapshot.restore(to: pb)

        return text?.isEmpty == true ? nil : text
    }

    // MARK: - Public API

    /// Read selected text via the Accessibility API (fast, no side effects).
    /// Returns nil for browsers that don't expose AXSelectedText (Safari, Chrome on macOS 26+).
    static func selectedTextViaAX(from element: AXUIElement? = nil) -> String? {
        // Direct read from focused element (works for most native apps)
        if let target = resolveTarget(element), let text = readSelectedText(target) {
            return text
        }

        // System-wide focused element
        if let sw = axAttribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString) {
            // CF types require force cast
            if let text = readSelectedText(sw as! AXUIElement) { return text }
        }

        return nil
    }

    /// Get the bounds of the selected text in screen coordinates
    static func selectedTextBounds(from element: AXUIElement? = nil) -> CGRect? {
        guard let target = resolveTarget(element) else { return nil }
        return selectedTextBoundsFromElement(target)
    }

    private static func selectedTextBoundsFromElement(_ target: AXUIElement) -> CGRect? {
        guard let range = axAttribute(target, kAXSelectedTextRangeAttribute as CFString) else {
            return elementBounds(target)
        }

        var boundsValue: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            target, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsValue
        ) == .success, let boundsRef = boundsValue {
            var bounds = CGRect.zero
            // CF types require force cast — AXValueGetValue validates the type internally
            if AXValueGetValue(boundsRef as! AXValue, .cgRect, &bounds) {
                return bounds
            }
        }

        return elementBounds(target)
    }

    static func isEditable(element: AXUIElement? = nil) -> Bool {
        guard let target = resolveTarget(element) else { return false }

        if let role = axAttribute(target, kAXRoleAttribute as CFString) as? String,
           role == kAXTextFieldRole || role == kAXTextAreaRole { return true }
        return axAttribute(target, "AXEditable" as CFString) as? Bool ?? false
    }

    /// Convert an AppKit screen point (bottom-left origin) to AX coordinates (top-left origin).
    static func axPoint(from screenPoint: CGPoint) -> CGPoint {
        let screenHeight = (NSScreen.main ?? NSScreen.screens.first)?.frame.height ?? 900
        return CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y)
    }

    /// Get selected text bounds, falling back to the current mouse position in AX coordinates.
    static func selectedTextBoundsOrMouse() -> CGRect {
        selectedTextBounds()
            ?? CGRect(origin: axPoint(from: NSEvent.mouseLocation), size: .zero)
    }

    private static func elementBounds(_ element: AXUIElement) -> CGRect? {
        guard let posValue = axAttribute(element, kAXPositionAttribute as CFString),
              let sizeValue = axAttribute(element, kAXSizeAttribute as CFString)
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        // CF types require force cast — AXValueGetValue validates the type internally
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }
}

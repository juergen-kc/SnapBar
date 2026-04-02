import AppKit
import ApplicationServices
import os

enum AccessibilityHelper {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Read an accessibility attribute, returning nil on failure.
    private static func axAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    /// Get the currently focused UI element
    static func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // AXUIElement is a CFTypeRef — force cast is required for CF types
        return axAttribute(axApp, kAXFocusedUIElementAttribute as CFString) as! AXUIElement?
    }

    /// Resolve a target element: use the provided element, fall back to focused, then system-wide.
    private static func resolveTarget(_ element: AXUIElement? = nil) -> AXUIElement? {
        if let element { return element }
        if let focused = focusedElement() { return focused }

        // Fallback: system-wide focused element
        let systemWide = AXUIElementCreateSystemWide()
        return axAttribute(systemWide, kAXFocusedUIElementAttribute as CFString) as! AXUIElement?
    }

    /// Get the selected text from the focused element
    static func selectedText(from element: AXUIElement? = nil) -> String? {
        guard let target = resolveTarget(element) else { return nil }

        if let text = axAttribute(target, kAXSelectedTextAttribute as CFString) as? String, !text.isEmpty {
            return text
        }

        // Fallback: try the system-wide element directly (may differ from resolveTarget's result)
        let systemWide = AXUIElementCreateSystemWide()
        guard let systemFocused = axAttribute(systemWide, kAXFocusedUIElementAttribute as CFString) else { return nil }

        if let text = axAttribute(systemFocused as! AXUIElement, kAXSelectedTextAttribute as CFString) as? String, !text.isEmpty {
            return text
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
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            target,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        )

        if boundsResult == .success, let boundsRef = boundsValue {
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

        let roleStr = axAttribute(target, kAXRoleAttribute as CFString) as? String ?? ""

        if roleStr == kAXTextFieldRole || roleStr == kAXTextAreaRole {
            return true
        }

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

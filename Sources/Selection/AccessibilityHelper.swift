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

    /// Get the currently focused UI element
    static func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return nil }
        // AXUIElement is a CFTypeRef — force cast is required for CF types
        return (element as! AXUIElement)
    }

    /// Resolve a target element: use the provided element, fall back to focused, then system-wide.
    private static func resolveTarget(_ element: AXUIElement? = nil) -> AXUIElement? {
        if let element { return element }
        if let focused = focusedElement() { return focused }

        // Fallback: system-wide focused element
        let systemWide = AXUIElementCreateSystemWide()
        var systemFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &systemFocused) == .success
        else { return nil }
        return (systemFocused as! AXUIElement)
    }

    /// Get the selected text from the focused element
    static func selectedText(from element: AXUIElement? = nil) -> String? {
        guard let target = resolveTarget(element) else { return nil }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(target, kAXSelectedTextAttribute as CFString, &value)

        if result == .success, let text = value as? String, !text.isEmpty {
            return text
        }

        // Fallback: try the system-wide element directly (may differ from resolveTarget's result)
        let systemWide = AXUIElementCreateSystemWide()
        var systemFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &systemFocused) == .success
        else { return nil }

        var sysValue: CFTypeRef?
        let sysResult = AXUIElementCopyAttributeValue(systemFocused as! AXUIElement, kAXSelectedTextAttribute as CFString, &sysValue)
        if sysResult == .success, let text = sysValue as? String, !text.isEmpty {
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
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard rangeResult == .success, let range = rangeValue else { return elementBounds(target) }

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

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(target, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String ?? ""

        if roleStr == kAXTextFieldRole || roleStr == kAXTextAreaRole {
            return true
        }

        var editable: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(target, "AXEditable" as CFString, &editable)
        if result == .success, let isEditable = editable as? Bool {
            return isEditable
        }

        return false
    }

    /// Convert an AppKit screen point (bottom-left origin) to AX coordinates (top-left origin).
    static func axPoint(from screenPoint: CGPoint) -> CGPoint {
        let screenHeight = NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 900
        return CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y)
    }

    private static func elementBounds(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        // CF types require force cast — AXValueGetValue validates the type internally
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }
}

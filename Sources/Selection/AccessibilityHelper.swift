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

    /// Get the selected text from the focused element
    static func selectedText(from element: AXUIElement? = nil) -> String? {
        let target: AXUIElement
        if let element {
            target = element
        } else if let focused = focusedElement() {
            target = focused
        } else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(target, kAXSelectedTextAttribute as CFString, &value)

        if result == .success, let text = value as? String, !text.isEmpty {
            return text
        }

        // Fallback: try the system-wide element
        let systemWide = AXUIElementCreateSystemWide()
        var systemFocused: CFTypeRef?
        let sysResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &systemFocused)
        if sysResult == .success, let sysElement = systemFocused {
            var sysValue: CFTypeRef?
            let textResult = AXUIElementCopyAttributeValue(sysElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &sysValue)
            if textResult == .success, let text = sysValue as? String, !text.isEmpty {
                return text
            }
        }

        return nil
    }

    /// Get the bounds of the selected text in screen coordinates
    static func selectedTextBounds(from element: AXUIElement? = nil) -> CGRect? {
        let target: AXUIElement
        if let element {
            target = element
        } else if let focused = focusedElement() {
            target = focused
        } else {
            // Try system-wide
            let systemWide = AXUIElementCreateSystemWide()
            var systemFocused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &systemFocused) == .success,
                  let sysElement = systemFocused else { return nil }
            return selectedTextBoundsFromElement(sysElement as! AXUIElement)
        }
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
        let target: AXUIElement
        if let element {
            target = element
        } else if let focused = focusedElement() {
            target = focused
        } else {
            return false
        }

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

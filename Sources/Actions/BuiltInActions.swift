import AppKit

// MARK: - Copy

struct CopyAction: Action {
    let id = "copy"
    let title = "Copy"
    let icon = "doc.on.doc"

    func isApplicable(for selection: TextSelection) -> Bool { true }

    func execute(with selection: TextSelection) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection.text, forType: .string)
    }
}

// MARK: - Cut

struct CutAction: Action {
    let id = "cut"
    let title = "Cut"
    let icon = "scissors"

    func isApplicable(for selection: TextSelection) -> Bool {
        selection.isEditable
    }

    func execute(with selection: TextSelection) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection.text, forType: .string)
        // Simulate ⌘X via key event to let the app handle deletion
        simulateKeyPress(key: .x, modifiers: .maskCommand)
    }
}

// MARK: - Paste

struct PasteAction: Action {
    let id = "paste"
    let title = "Paste"
    let icon = "doc.on.clipboard"

    func isApplicable(for selection: TextSelection) -> Bool {
        selection.isEditable && NSPasteboard.general.string(forType: .string) != nil
    }

    func execute(with selection: TextSelection) {
        simulateKeyPress(key: .v, modifiers: .maskCommand)
    }
}

// MARK: - Search

struct SearchAction: Action {
    let id = "search"
    let title = "Search"
    let icon = "magnifyingglass"

    func isApplicable(for selection: TextSelection) -> Bool { true }

    func execute(with selection: TextSelection) {
        guard let encoded = selection.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        else { return }

        NSWorkspace.shared.open(url)
    }
}

// MARK: - Open Link

struct OpenLinkAction: Action {
    let id = "openLink"
    let title = "Open Link"
    let icon = "link"

    func isApplicable(for selection: TextSelection) -> Bool {
        extractURL(from: selection.text) != nil
    }

    func execute(with selection: TextSelection) {
        guard let url = extractURL(from: selection.text) else { return }
        NSWorkspace.shared.open(url)
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count < 2048 else { return nil }  // Guard against huge selections

        // Try direct URL parsing
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        // Try adding https:// for URL-like text
        let urlPattern = #"^[\w][\w.-]*\.[a-zA-Z]{2,}(/\S*)?$"#
        if trimmed.range(of: urlPattern, options: .regularExpression) != nil {
            return URL(string: "https://\(trimmed)")
        }

        // Try to find a URL within the text using NSDataDetector
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let match = Self.linkDetector?.firstMatch(in: trimmed, range: range), let url = match.url {
            return url
        }

        return nil
    }
}

// MARK: - Dictionary

struct DictionaryAction: Action {
    let id = "dictionary"
    let title = "Dictionary"
    let icon = "book"

    func isApplicable(for selection: TextSelection) -> Bool {
        let trimmed = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only show for single words or short phrases
        let wordCount = trimmed.components(separatedBy: .whitespaces).count
        return wordCount <= 3 && !trimmed.isEmpty
    }

    func execute(with selection: TextSelection) {
        let trimmed = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Open Dictionary.app with the word
        let script = "tell application \"Dictionary\" to activate"
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
        // Use the system dictionary lookup
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "dict://\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Key Simulation Helper

func simulateKeyPress(key: KeyEquivalent, modifiers: CGEventFlags) {
    let keyCode = key.carbonKeyCode
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else { return }

    keyDown.flags = modifiers
    keyUp.flags = modifiers
    keyDown.post(tap: .cgAnnotatedSessionEventTap)
    keyUp.post(tap: .cgAnnotatedSessionEventTap)
}

/// Maps SwiftUI KeyEquivalent-like values to Carbon key codes
enum KeyEquivalent {
    case x, v, c

    var carbonKeyCode: CGKeyCode {
        switch self {
        case .x: 7   // kVK_ANSI_X
        case .v: 9   // kVK_ANSI_V
        case .c: 8   // kVK_ANSI_C
        }
    }
}

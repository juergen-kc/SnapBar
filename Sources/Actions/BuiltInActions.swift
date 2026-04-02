import AppKit

// MARK: - Copy

struct CopyAction: Action {
    let id = "copy"
    let title = "Copy"
    let icon = "doc.on.doc"

    func isApplicable(for selection: TextSelection) -> Bool { true }

    func execute(with selection: TextSelection) {
        copyToClipboard(selection.text)
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
        copyToClipboard(selection.text)
        // Simulate ⌘X via key event to let the app handle deletion
        simulateKeyPress(keyCode: carbonKeyCode(for: "x")!, modifiers: .maskCommand)
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
        simulateKeyPress(keyCode: carbonKeyCode(for: "v")!, modifiers: .maskCommand)
    }
}

// MARK: - Search

struct SearchAction: Action {
    let id = "search"
    let title = "Search"
    let icon = "magnifyingglass"

    func isApplicable(for selection: TextSelection) -> Bool { true }

    func execute(with selection: TextSelection) {
        let engine = MainActor.assumeIsolated { AppState.shared?.searchEngine } ?? .google
        guard let url = engine.searchURL(for: selection.text) else { return }
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

// MARK: - Paste as Plain Text

struct PastePlainTextAction: Action {
    let id = "pastePlainText"
    let title = "Paste as Plain Text"
    let icon = "doc.plaintext"

    func isApplicable(for selection: TextSelection) -> Bool {
        selection.isEditable && NSPasteboard.general.string(forType: .string) != nil
    }

    func execute(with selection: TextSelection) {
        guard let plainText = NSPasteboard.general.string(forType: .string) else { return }
        // Re-set clipboard with plain text only (stripping rich formatting), then paste
        pasteReplacingSelection(plainText, isEditable: true)
    }
}

// MARK: - Spelling

struct SpellingAction: Action {
    let id = "spelling"
    let title = "Spelling"
    let icon = "textformat.abc"

    func isApplicable(for selection: TextSelection) -> Bool {
        guard selection.isEditable else { return false }
        let trimmed = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only for single words or short text
        guard !trimmed.isEmpty, trimmed.count < 100 else { return false }

        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: trimmed, startingAt: 0)
        return range.location != NSNotFound
    }

    func execute(with selection: TextSelection) {
        let trimmed = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: trimmed, startingAt: 0)
        guard range.location != NSNotFound else { return }

        let misspelled = (trimmed as NSString).substring(with: range)
        let guesses = checker.guesses(forWordRange: range, in: trimmed, language: nil, inSpellDocumentWithTag: 0) ?? []

        if let firstGuess = guesses.first {
            let corrected = trimmed.replacingCharacters(
                in: Range(range, in: trimmed)!,
                with: firstGuess
            )
            pasteReplacingSelection(corrected, isEditable: true)
        }
    }
}

// MARK: - Reveal in Finder

struct RevealInFinderAction: Action {
    let id = "revealInFinder"
    let title = "Reveal in Finder"
    let icon = "folder"

    func isApplicable(for selection: TextSelection) -> Bool {
        extractPath(from: selection.text) != nil
    }

    func execute(with selection: TextSelection) {
        guard let path = extractPath(from: selection.text) else { return }
        let url = URL(fileURLWithPath: path)

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            if isDir.boolValue {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func extractPath(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count < 1024 else { return nil }

        // Expand ~ to home directory
        let expanded: String
        if trimmed.hasPrefix("~/") {
            expanded = NSString(string: trimmed).expandingTildeInPath
        } else if trimmed.hasPrefix("/") {
            expanded = trimmed
        } else {
            return nil
        }

        return FileManager.default.fileExists(atPath: expanded) ? expanded : nil
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

func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) {
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else { return }

    keyDown.flags = modifiers
    keyUp.flags = modifiers
    keyDown.post(tap: .cgAnnotatedSessionEventTap)
    keyUp.post(tap: .cgAnnotatedSessionEventTap)
}

/// Carbon virtual key code lookup
func carbonKeyCode(for key: String) -> CGKeyCode? {
    carbonKeyCodes[key.lowercased()]
}

private let carbonKeyCodes: [String: CGKeyCode] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
    "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35,
    "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
    "y": 16, "z": 6,
    "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
    "8": 28, "9": 25,
    "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "esc": 53,
    "delete": 51, "backspace": 51, "forwarddelete": 117,
    "up": 126, "down": 125, "left": 123, "right": 124,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
]

/// Copy text to the system clipboard.
func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Paste text into the focused field, restoring the previous clipboard after a short delay.
/// If the selection is not editable, just copies the text to the clipboard.
func pasteReplacingSelection(_ text: String, isEditable: Bool) {
    let previousClipboard = NSPasteboard.general.string(forType: .string)

    copyToClipboard(text)

    if isEditable {
        simulateKeyPress(keyCode: carbonKeyCodes["v"]!, modifiers: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let prev = previousClipboard {
                copyToClipboard(prev)
            }
        }
    }
}

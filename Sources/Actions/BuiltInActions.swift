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
        selection.isEditable && correction(for: selection.text) != nil
    }

    func execute(with selection: TextSelection) {
        guard let corrected = correction(for: selection.text) else { return }
        pasteReplacingSelection(corrected, isEditable: true)
    }

    /// Returns the corrected text if a misspelling is found, nil otherwise.
    private func correction(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 100 else { return nil }

        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: trimmed, startingAt: 0)
        guard range.location != NSNotFound else { return nil }

        guard let firstGuess = checker.guesses(forWordRange: range, in: trimmed, language: nil, inSpellDocumentWithTag: 0)?.first else { return nil }

        return trimmed.replacingCharacters(in: Range(range, in: trimmed)!, with: firstGuess)
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
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }

        if isDir.boolValue {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func extractPath(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count < 1024 else { return nil }

        let expanded: String
        if trimmed.hasPrefix("~/") { expanded = NSString(string: trimmed).expandingTildeInPath }
        else if trimmed.hasPrefix("/") { expanded = trimmed }
        else { return nil }

        return FileManager.default.fileExists(atPath: expanded) ? expanded : nil
    }
}

// MARK: - Dictionary

struct DictionaryAction: Action {
    let id = "dictionary"
    let title = "Dictionary"
    let icon = "book"

    func isApplicable(for selection: TextSelection) -> Bool {
        selection.hasContent && trimmed(selection).components(separatedBy: .whitespaces).count <= 3
    }

    func execute(with selection: TextSelection) {
        let word = trimmed(selection)
        if let appleScript = NSAppleScript(source: "tell application \"Dictionary\" to activate") {
            appleScript.executeAndReturnError(nil)
        }
        // Use the system dictionary lookup
        if let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "dict://\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func trimmed(_ selection: TextSelection) -> String {
        selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
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

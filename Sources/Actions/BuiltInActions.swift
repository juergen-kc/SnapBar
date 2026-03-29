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
        // Get the plain text from the clipboard
        guard let plainText = NSPasteboard.general.string(forType: .string) else { return }

        // Replace clipboard with plain text only (stripping rich formatting)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText, forType: .string)

        // Paste it
        simulateKeyPress(key: .v, modifiers: .maskCommand)
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
            // Replace misspelled word with the top suggestion
            let corrected = trimmed.replacingCharacters(
                in: Range(range, in: trimmed)!,
                with: firstGuess
            )

            // Save current clipboard, paste correction, restore
            let previous = NSPasteboard.general.string(forType: .string)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(corrected, forType: .string)
            simulateKeyPress(key: .v, modifiers: .maskCommand)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let prev = previous {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
            }
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

import AppKit

/// Wraps a PluginDefinition into an Action that the toolbar can display and execute.
struct PluginAction: Action {
    let definition: PluginDefinition

    var id: String { "plugin.\(definition.name)" }
    var title: String { definition.name }
    var icon: String { definition.icon }

    func isApplicable(for selection: TextSelection) -> Bool {
        // Check text length constraints
        if let min = definition.minLength, selection.text.count < min { return false }
        if let max = definition.maxLength, selection.text.count > max { return false }

        // Check regex filter
        if let pattern = definition.regex {
            guard selection.text.range(of: pattern, options: .regularExpression) != nil else { return false }
        }

        // Check app filter — if filter is set, require a matching bundle ID
        if let allowed = definition.appFilter {
            guard let bundleID = selection.bundleIdentifier, allowed.contains(bundleID) else { return false }
        }

        // Check app exclusion
        if let excluded = definition.appExclude, let bundleID = selection.bundleIdentifier {
            if excluded.contains(bundleID) { return false }
        }

        return true
    }

    func execute(with selection: TextSelection) {
        switch definition.type {
        case .url:
            executeURL(with: selection)
        case .script:
            executeScript(with: selection)
        case .shortcut:
            executeShortcut(with: selection)
        case .keyCombo:
            executeKeyCombo()
        case .copyTransform:
            executeCopyTransform(with: selection)
        case .service:
            executeService(with: selection)
        }
    }

    // MARK: - Executors

    private func executeService(with selection: TextSelection) {
        guard let serviceName = definition.serviceName else {
            DebugLog.log("Service plugin '\(definition.name)' has no serviceName")
            return
        }

        // Put selected text on a pasteboard for the service
        let pboard = NSPasteboard(name: .init("SnapBarService"))
        pboard.clearContents()
        pboard.setString(selection.text, forType: .string)

        // Perform the service
        let success = NSPerformService(serviceName, pboard)

        if success {
            // Check if the service returned modified text
            if let result = pboard.string(forType: .string), result != selection.text {
                // Service modified the text — paste it back if editable
                if selection.isEditable {
                    let previousClipboard = NSPasteboard.general.string(forType: .string)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    simulateKeyPress(key: .v, modifiers: .maskCommand)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let prev = previousClipboard {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(prev, forType: .string)
                        }
                    }
                } else {
                    // Not editable — just copy result to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                }
            }
            DebugLog.log("Service '\(serviceName)' executed successfully")
        } else {
            DebugLog.log("Service '\(serviceName)' failed or not found")
        }
    }

    private func executeURL(with selection: TextSelection) {
        guard let template = definition.url else { return }
        guard let encoded = selection.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        let urlString = template.replacingOccurrences(of: "{text}", with: encoded)
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func executeScript(with selection: TextSelection) {
        guard let script = definition.script else { return }
        let interpreter = definition.scriptInterpreter ?? "/bin/bash"

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: interpreter)

            if interpreter.contains("osascript") {
                process.arguments = ["-e", script]
            } else {
                process.arguments = ["-c", script]
            }

            // Pass selected text as environment variable and stdin
            var env = ProcessInfo.processInfo.environment
            env["SNAPBAR_TEXT"] = selection.text
            process.environment = env

            let inputPipe = Pipe()
            process.standardInput = inputPipe
            let outputPipe = Pipe()
            process.standardOutput = outputPipe

            try? process.run()

            // Write selected text to stdin
            inputPipe.fileHandleForWriting.write(Data(selection.text.utf8))
            inputPipe.fileHandleForWriting.closeFile()

            process.waitUntilExit()

            // If the script produced output, copy it to clipboard
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                }
            }
        }
    }

    private func executeShortcut(with selection: TextSelection) {
        guard let name = definition.shortcutName else { return }
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name, "--input-path", "-"]

            let inputPipe = Pipe()
            process.standardInput = inputPipe

            try? process.run()
            inputPipe.fileHandleForWriting.write(Data(selection.text.utf8))
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        }
    }

    private func executeKeyCombo() {
        guard let combo = definition.keyCombo else { return }
        let parts = combo.lowercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }

        var flags: CGEventFlags = []
        var keyChar: String?

        for part in parts {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: keyChar = part
            }
        }

        guard let char = keyChar, let code = carbonKeyCode(for: char) else { return }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func executeCopyTransform(with selection: TextSelection) {
        guard let transform = definition.transform else { return }
        let result: String

        switch transform {
        case .uppercase:
            result = selection.text.uppercased()
        case .lowercase:
            result = selection.text.lowercased()
        case .titlecase:
            result = selection.text.capitalized
        case .capitalize:
            let first = selection.text.prefix(1).uppercased()
            let rest = selection.text.dropFirst()
            result = first + rest
        case .trimWhitespace:
            result = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .base64Encode:
            result = Data(selection.text.utf8).base64EncodedString()
        case .base64Decode:
            if let data = Data(base64Encoded: selection.text), let decoded = String(data: data, encoding: .utf8) {
                result = decoded
            } else {
                result = selection.text
            }
        case .urlEncode:
            result = selection.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selection.text
        case .urlDecode:
            result = selection.text.removingPercentEncoding ?? selection.text
        case .markdownBold:
            result = "**\(selection.text)**"
        case .markdownItalic:
            result = "*\(selection.text)*"
        case .markdownCode:
            result = selection.text.contains("\n") ? "```\n\(selection.text)\n```" : "`\(selection.text)`"
        case .countWords:
            let count = selection.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            result = "\(count) words"
        case .countCharacters:
            result = "\(selection.text.count) characters"
        case .sortLines:
            result = selection.text.components(separatedBy: .newlines).sorted().joined(separator: "\n")
        case .reverseLines:
            result = selection.text.components(separatedBy: .newlines).reversed().joined(separator: "\n")
        case .removeBlankLines:
            result = selection.text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        }

        // Save current clipboard, set result, paste if editable, then restore
        let previousClipboard = NSPasteboard.general.string(forType: .string)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)

        if selection.isEditable {
            // Paste to replace the selected text
            simulateKeyPress(key: .v, modifiers: .maskCommand)

            // Restore previous clipboard after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let prev = previousClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
            }
        }
    }

    // MARK: - Key Code Mapping

    private func carbonKeyCode(for character: String) -> CGKeyCode? {
        let map: [String: CGKeyCode] = [
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
        return map[character.lowercased()]
    }
}

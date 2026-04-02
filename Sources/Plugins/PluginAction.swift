import AppKit
import JavaScriptCore

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
        case .javascript:
            executeJavaScript(with: selection)
        }
    }

    // MARK: - Executors

    private func executeService(with selection: TextSelection) {
        guard let serviceName = definition.serviceName else {
            DebugLog.log("Service plugin '\(definition.name)' has no serviceName")
            return
        }

        let pboard = NSPasteboard(name: .init("SnapBarService"))
        pboard.clearContents()
        pboard.setString(selection.text, forType: .string)

        let success = NSPerformService(serviceName, pboard)

        if success {
            if let result = pboard.string(forType: .string), result != selection.text {
                pasteReplacingSelection(result, isEditable: selection.isEditable)
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
                    copyToClipboard(output)
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
        simulateKeyPress(keyCode: code, modifiers: flags)
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

        pasteReplacingSelection(result, isEditable: selection.isEditable)
    }

    private func executeJavaScript(with selection: TextSelection) {
        guard let code = definition.jsCode else {
            DebugLog.log("JavaScript plugin '\(definition.name)' has no jsCode")
            return
        }

        guard let context = JSContext() else {
            DebugLog.log("Failed to create JSContext")
            return
        }

        // Set up exception handler
        context.exceptionHandler = { _, exception in
            DebugLog.log("JS error in '\(self.definition.name)': \(exception?.toString() ?? "unknown")")
        }

        // Provide the selected text as `input`
        context.setObject(selection.text, forKeyedSubscript: "input" as NSString)

        // Evaluate the script
        guard let result = context.evaluateScript(code) else { return }

        if !result.isUndefined, !result.isNull, let output = result.toString(), !output.isEmpty {
            pasteReplacingSelection(output, isEditable: selection.isEditable)
        }
    }

}

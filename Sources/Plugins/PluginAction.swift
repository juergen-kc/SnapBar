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
        if let excluded = definition.appExclude, let bundleID = selection.bundleIdentifier,
           excluded.contains(bundleID) { return false }

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

        guard NSPerformService(serviceName, pboard) else {
            DebugLog.log("Service '\(serviceName)' failed or not found")
            return
        }

        if let result = pboard.string(forType: .string), result != selection.text {
            pasteReplacingSelection(result, isEditable: selection.isEditable)
        }
        DebugLog.log("Service '\(serviceName)' executed successfully")
    }

    private func executeURL(with selection: TextSelection) {
        guard let template = definition.url else { return }
        guard let encoded = selection.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: template.replacingOccurrences(of: "{text}", with: encoded)) else { return }
        NSWorkspace.shared.open(url)
    }

    private func executeScript(with selection: TextSelection) {
        guard let script = definition.script else { return }
        let interpreter = definition.scriptInterpreter ?? "/bin/bash"

        let arguments = interpreter.contains("osascript") ? ["-e", script] : ["-c", script]

        var env = ProcessInfo.processInfo.environment
        env["SNAPBAR_TEXT"] = selection.text

        Task.detached {
            if let output = runProcess(
                executable: interpreter, arguments: arguments,
                input: selection.text, environment: env, captureOutput: true
            ), !output.isEmpty {
                await MainActor.run { copyToClipboard(output) }
            }
        }
    }

    private func executeShortcut(with selection: TextSelection) {
        guard let name = definition.shortcutName else { return }
        Task.detached {
            runProcess(
                executable: "/usr/bin/shortcuts",
                arguments: ["run", name, "--input-path", "-"],
                input: selection.text
            )
        }
    }

    private static let modifierMap: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "alt": .maskAlternate, "option": .maskAlternate, "opt": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl,
    ]

    private func executeKeyCombo() {
        guard let combo = definition.keyCombo else { return }
        let parts = combo.lowercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }

        let flags = parts.compactMap { Self.modifierMap[$0] }.reduce(CGEventFlags()) { $0.union($1) }
        guard let keyChar = parts.last(where: { Self.modifierMap[$0] == nil }),
              let code = carbonKeyCode(for: keyChar) else { return }
        simulateKeyPress(keyCode: code, modifiers: flags)
    }

    private func executeCopyTransform(with selection: TextSelection) {
        guard let transform = definition.transform else { return }
        let text = selection.text

        let result = switch transform {
        case .uppercase: text.uppercased()
        case .lowercase: text.lowercased()
        case .titlecase: text.capitalized
        case .capitalize: text.prefix(1).uppercased() + text.dropFirst()
        case .trimWhitespace: text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .base64Encode: Data(text.utf8).base64EncodedString()
        case .base64Decode: Data(base64Encoded: text).flatMap { String(data: $0, encoding: .utf8) } ?? text
        case .urlEncode: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case .urlDecode: text.removingPercentEncoding ?? text
        case .markdownBold: "**\(text)**"
        case .markdownItalic: "*\(text)*"
        case .markdownCode: text.contains("\n") ? "```\n\(text)\n```" : "`\(text)`"
        case .countWords: "\(text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count) words"
        case .countCharacters: "\(text.count) characters"
        case .sortLines: text.components(separatedBy: .newlines).sorted().joined(separator: "\n")
        case .reverseLines: text.components(separatedBy: .newlines).reversed().joined(separator: "\n")
        case .removeBlankLines: text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        }

        pasteReplacingSelection(result, isEditable: selection.isEditable)
    }

    /// Run a subprocess with optional stdin input and output capture.
    @discardableResult
    private func runProcess(
        executable: String, arguments: [String],
        input: String, environment: [String: String]? = nil,
        captureOutput: Bool = false
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let inputPipe = Pipe()
        process.standardInput = inputPipe

        let outputPipe = captureOutput ? Pipe() : nil
        if let outputPipe { process.standardOutput = outputPipe }

        try? process.run()
        inputPipe.fileHandleForWriting.write(Data(input.utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        guard let outputPipe else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
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

import Foundation

/// Loads plugin definitions from ~/.snapbar/plugins/
enum PluginLoader {
    static let pluginsDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".snapbar/plugins", isDirectory: true)
    }()

    /// Ensure the plugins directory exists
    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
    }

    /// Load all plugins from disk
    static func loadAll() -> [PluginDefinition] {
        ensureDirectory()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let pluginFiles = files.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "yaml" || ext == "yml" || ext == "json"
        }

        return pluginFiles.compactMap { loadPlugin(from: $0) }
    }

    /// Load a single plugin file
    static func loadPlugin(from url: URL) -> PluginDefinition? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let ext = url.pathExtension.lowercased()

        if ext == "json" {
            return try? JSONDecoder().decode(PluginDefinition.self, from: data)
        }

        // For YAML, we use a simple key-value parser since we don't want a dependency
        guard let content = String(data: data, encoding: .utf8) else { return nil }
        return parseYAML(content)
    }

    /// Parse a snippet string (plain text starting with #snapbar)
    static func parseSnippet(_ text: String) -> PluginDefinition? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#snapbar") else { return nil }
        // Remove the #snapbar marker and parse as YAML
        let content = String(trimmed.dropFirst("#snapbar".count))
        return parseYAML(content)
    }

    /// Install a plugin by writing it to the plugins directory
    static func install(_ definition: PluginDefinition) throws {
        ensureDirectory()
        let filename = definition.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let url = pluginsDirectory.appendingPathComponent("\(filename).json")
        let data = try JSONEncoder().encode(definition)
        try data.write(to: url)
    }

    // MARK: - Simple YAML Parser

    /// Minimal YAML parser for flat key-value pairs (no nesting beyond arrays)
    private static func parseYAML(_ content: String) -> PluginDefinition? {
        var dict: [String: String] = [:]
        var arrayValues: [String: [String]] = [:]

        var currentArrayKey: String?
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Array item
            if trimmed.hasPrefix("- "), let key = currentArrayKey {
                let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                arrayValues[key, default: []].append(value)
                continue
            }

            currentArrayKey = nil

            // Key-value pair
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

                if value.isEmpty {
                    // Next lines might be array items
                    currentArrayKey = key
                } else {
                    // Strip quotes
                    let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    dict[key] = unquoted
                }
            }
        }

        guard let name = dict["name"],
              let icon = dict["icon"],
              let typeStr = dict["type"],
              let type = PluginDefinition.PluginType(rawValue: typeStr) else {
            return nil
        }

        return PluginDefinition(
            name: name,
            icon: icon,
            type: type,
            regex: dict["regex"],
            appFilter: arrayValues["app_filter"],
            appExclude: arrayValues["app_exclude"],
            minLength: dict["min_length"].flatMap(Int.init),
            maxLength: dict["max_length"].flatMap(Int.init),
            url: dict["url"],
            script: dict["script"],
            scriptInterpreter: dict["script_interpreter"] ?? dict["interpreter"],
            shortcutName: dict["shortcut_name"] ?? dict["shortcut"],
            keyCombo: dict["key_combo"],
            transform: dict["transform"].flatMap(PluginDefinition.TextTransform.init(rawValue:)),
            serviceName: dict["service_name"] ?? dict["service"]
        )
    }
}

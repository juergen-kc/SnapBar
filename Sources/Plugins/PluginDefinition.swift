import Foundation

/// Represents a plugin loaded from YAML/JSON on disk.
struct PluginDefinition: Codable, Identifiable {
    let name: String
    let icon: String               // SF Symbol name or emoji
    let type: PluginType

    // Context filters (all optional)
    var regex: String?             // Only show when text matches this regex
    var appFilter: [String]?       // Only show in these bundle IDs
    var appExclude: [String]?      // Hide in these bundle IDs
    var minLength: Int?
    var maxLength: Int?

    // Type-specific fields
    var url: String?               // For .url type — use {text} placeholder
    var script: String?            // For .script type — shell/osascript source
    var scriptInterpreter: String? // e.g. "/bin/bash", "/usr/bin/osascript"
    var shortcutName: String?      // For .shortcut type — Shortcuts.app shortcut name
    var keyCombo: String?          // For .keyCombo type — e.g. "cmd+shift+k"
    var transform: TextTransform?  // For .copyTransform type
    var serviceName: String?       // For .service type — macOS Services menu name

    var id: String { name }

    enum PluginType: String, Codable {
        case url
        case script
        case shortcut
        case keyCombo = "key_combo"
        case copyTransform = "copy_transform"
        case service
    }

    enum TextTransform: String, Codable {
        case uppercase
        case lowercase
        case titlecase
        case capitalize
        case trimWhitespace = "trim_whitespace"
        case base64Encode = "base64_encode"
        case base64Decode = "base64_decode"
        case urlEncode = "url_encode"
        case urlDecode = "url_decode"
        case markdownBold = "markdown_bold"
        case markdownItalic = "markdown_italic"
        case markdownCode = "markdown_code"
        case countWords = "count_words"
        case countCharacters = "count_characters"
        case sortLines = "sort_lines"
        case reverseLines = "reverse_lines"
        case removeBlankLines = "remove_blank_lines"
    }
}

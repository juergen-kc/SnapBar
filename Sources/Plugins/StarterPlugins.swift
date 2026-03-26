import Foundation

/// Installs the starter plugin pack into ~/.snapbar/plugins/ if it's empty.
enum StarterPlugins {
    static func installIfNeeded() {
        let dir = PluginLoader.pluginsDirectory
        PluginLoader.ensureDirectory()

        // Only install if the directory is empty
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let pluginFiles = existing.filter { $0.hasSuffix(".yaml") || $0.hasSuffix(".yml") || $0.hasSuffix(".json") }
        guard pluginFiles.isEmpty else { return }

        for (filename, content) in plugins {
            let url = dir.appendingPathComponent(filename)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static let plugins: [(String, String)] = [
        ("translate.yaml", """
        name: Translate
        icon: globe
        type: url
        url: "https://translate.google.com/?sl=auto&tl=en&text={text}"
        min_length: 1
        """),

        ("uppercase.yaml", """
        name: UPPERCASE
        icon: textformat.size.larger
        type: copy_transform
        transform: uppercase
        """),

        ("lowercase.yaml", """
        name: lowercase
        icon: textformat.size.smaller
        type: copy_transform
        transform: lowercase
        """),

        ("title-case.yaml", """
        name: Title Case
        icon: textformat
        type: copy_transform
        transform: titlecase
        """),

        ("word-count.yaml", """
        name: Word Count
        icon: number
        type: copy_transform
        transform: count_words
        """),

        ("base64-encode.yaml", """
        name: Base64 Encode
        icon: lock
        type: copy_transform
        transform: base64_encode
        """),

        ("base64-decode.yaml", """
        name: Base64 Decode
        icon: lock.open
        type: copy_transform
        transform: base64_decode
        regex: "^[A-Za-z0-9+/=]+$"
        """),

        ("maps.yaml", """
        name: Maps
        icon: map
        type: url
        url: "https://maps.apple.com/?q={text}"
        min_length: 3
        """),

        ("email.yaml", """
        name: Email
        icon: envelope
        type: url
        url: "mailto:{text}"
        regex: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
        """),

        ("markdown-bold.yaml", """
        name: Bold
        icon: bold
        type: copy_transform
        transform: markdown_bold
        """),
    ]
}

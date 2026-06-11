import Testing
@testable import SnapBar

@Suite("PluginLoader YAML parser")
struct PluginLoaderTests {

    // Convenience: prepend the required #snapbar marker
    private func parse(_ yaml: String) -> PluginDefinition? {
        PluginLoader.parseSnippet("#snapbar\n" + yaml)
    }

    // MARK: - Marker requirement

    @Test func rejectsSnippetWithoutMarker() {
        #expect(PluginLoader.parseSnippet("name: P\nicon: s\ntype: url") == nil)
    }

    @Test func acceptsSnippetWithMarker() {
        #expect(parse("name: P\nicon: s\ntype: url") != nil)
    }

    // MARK: - Required fields

    @Test func parsesRequiredFields() throws {
        let def = try #require(parse("name: My Plugin\nicon: star\ntype: url"))
        #expect(def.name == "My Plugin")
        #expect(def.icon == "star")
        #expect(def.type == .url)
    }

    @Test func rejectsMissingName() {
        #expect(parse("icon: star\ntype: url") == nil)
    }

    @Test func rejectsMissingIcon() {
        #expect(parse("name: P\ntype: url") == nil)
    }

    @Test func rejectsMissingType() {
        #expect(parse("name: P\nicon: s") == nil)
    }

    @Test func rejectsUnknownType() {
        #expect(parse("name: P\nicon: s\ntype: unknown_type") == nil)
    }

    @Test func rejectsEmptyNameValue() {
        // "name: " has an empty value — treated as potential array key, never assigned
        #expect(parse("name: \nicon: s\ntype: url") == nil)
    }

    // MARK: - All valid plugin types

    @Test(arguments: zip(
        ["url", "script", "shortcut", "key_combo", "copy_transform", "service", "javascript"],
        [PluginDefinition.PluginType.url, .script, .shortcut, .keyCombo, .copyTransform, .service, .javascript]
    ))
    func parsesAllTypes(raw: String, expected: PluginDefinition.PluginType) throws {
        let def = try #require(parse("name: P\nicon: s\ntype: \(raw)"))
        #expect(def.type == expected)
    }

    // MARK: - Quote stripping

    @Test func stripsDoubleQuotes() throws {
        let def = try #require(parse("name: \"Quoted Plugin\"\nicon: \"star.fill\"\ntype: url"))
        #expect(def.name == "Quoted Plugin")
        #expect(def.icon == "star.fill")
    }

    @Test func stripsSingleQuotes() throws {
        let def = try #require(parse("name: 'Single Quoted'\nicon: 'star'\ntype: url"))
        #expect(def.name == "Single Quoted")
        #expect(def.icon == "star")
    }

    // MARK: - Comments and whitespace

    @Test func ignoresHashComments() throws {
        let def = try #require(parse("""
            # this is a comment
            name: My Plugin
            # another comment
            icon: star
            type: url
            """))
        #expect(def.name == "My Plugin")
    }

    @Test func ignoresBlankLines() throws {
        let def = try #require(parse("""

            name: My Plugin

            icon: star
            type: url

            """))
        #expect(def.name == "My Plugin")
    }

    // MARK: - Integer fields

    @Test func parsesLengthBounds() throws {
        let def = try #require(parse("name: P\nicon: s\ntype: url\nmin_length: 3\nmax_length: 200"))
        #expect(def.minLength == 3)
        #expect(def.maxLength == 200)
    }

    @Test func treatsNonIntegerLengthAsNil() throws {
        let def = try #require(parse("name: P\nicon: s\ntype: url\nmin_length: abc"))
        #expect(def.minLength == nil)
    }

    // MARK: - Array fields

    @Test func parsesAppFilterArray() throws {
        let def = try #require(parse("""
            name: P
            icon: s
            type: url
            app_filter:
            - com.apple.Safari
            - com.google.Chrome
            """))
        #expect(def.appFilter == ["com.apple.Safari", "com.google.Chrome"])
    }

    @Test func parsesAppExcludeArray() throws {
        let def = try #require(parse("""
            name: P
            icon: s
            type: url
            app_exclude:
            - com.apple.Terminal
            """))
        #expect(def.appExclude == ["com.apple.Terminal"])
    }

    @Test func arrayItemsAfterValueKeyAreIgnored() throws {
        // array items that appear before any empty-value key are discarded
        let def = try #require(parse("""
            name: P
            icon: s
            type: url
            app_filter:
            - com.apple.Safari
            url: https://example.com/{text}
            - this.is.not.a.filter.item
            """))
        #expect(def.appFilter == ["com.apple.Safari"])
        #expect(def.url == "https://example.com/{text}")
    }

    // MARK: - Optional string fields

    @Test func parsesRegex() throws {
        let def = try #require(parse("name: P\nicon: s\ntype: url\nregex: ^https?://"))
        #expect(def.regex == "^https?://")
    }

    @Test func parsesGroup() throws {
        let def = try #require(parse("name: P\nicon: s\ntype: url\ngroup: AI Tools"))
        #expect(def.group == "AI Tools")
    }

    @Test func preservesColonInURLValue() throws {
        // Parser uses firstIndex(of:) so only the first colon is the key/value separator
        let def = try #require(parse("name: P\nicon: s\ntype: url\nurl: https://example.com/{text}"))
        #expect(def.url == "https://example.com/{text}")
    }

    @Test func parsesCopyTransformField() throws {
        let def = try #require(parse("name: P\nicon: s\ntype: copy_transform\ntransform: uppercase"))
        #expect(def.transform == .uppercase)
    }

    @Test func treatsUnknownTransformAsNil() throws {
        let def = try #require(parse("name: P\nicon: s\ntype: copy_transform\ntransform: invented_transform"))
        #expect(def.transform == nil)
    }

    // MARK: - Alias keys

    @Test func acceptsBothShortcutAliases() throws {
        let d1 = try #require(parse("name: P\nicon: s\ntype: shortcut\nshortcut: My Shortcut"))
        let d2 = try #require(parse("name: P\nicon: s\ntype: shortcut\nshortcut_name: My Shortcut"))
        #expect(d1.shortcutName == "My Shortcut")
        #expect(d2.shortcutName == "My Shortcut")
    }

    @Test func acceptsBothServiceAliases() throws {
        let d1 = try #require(parse("name: P\nicon: s\ntype: service\nservice: Open in Finder"))
        let d2 = try #require(parse("name: P\nicon: s\ntype: service\nservice_name: Open in Finder"))
        #expect(d1.serviceName == "Open in Finder")
        #expect(d2.serviceName == "Open in Finder")
    }

    @Test func acceptsAllJavaScriptAliases() throws {
        let code = "input.toUpperCase()"
        let d1 = try #require(parse("name: P\nicon: s\ntype: javascript\njs: \(code)"))
        let d2 = try #require(parse("name: P\nicon: s\ntype: javascript\njavascript: \(code)"))
        let d3 = try #require(parse("name: P\nicon: s\ntype: javascript\njs_code: \(code)"))
        #expect(d1.jsCode == code)
        #expect(d2.jsCode == code)
        #expect(d3.jsCode == code)
    }

    @Test func acceptsBothInterpreterAliases() throws {
        let d1 = try #require(parse("name: P\nicon: s\ntype: script\nscript: echo hi\ninterpreter: /bin/bash"))
        let d2 = try #require(parse("name: P\nicon: s\ntype: script\nscript: echo hi\nscript_interpreter: /bin/zsh"))
        #expect(d1.scriptInterpreter == "/bin/bash")
        #expect(d2.scriptInterpreter == "/bin/zsh")
    }

    // MARK: - isPluginFile

    @Test func recognizesPluginFileExtensions() {
        #expect(PluginLoader.isPluginFile("yaml"))
        #expect(PluginLoader.isPluginFile("yml"))
        #expect(PluginLoader.isPluginFile("json"))
        #expect(PluginLoader.isPluginFile("YAML"))  // case-insensitive
        #expect(PluginLoader.isPluginFile("JSON"))
        #expect(!PluginLoader.isPluginFile("txt"))
        #expect(!PluginLoader.isPluginFile("swift"))
        #expect(!PluginLoader.isPluginFile(""))
    }
}

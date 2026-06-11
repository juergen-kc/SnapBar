import Testing
import AppKit
@testable import SnapBar

// MARK: - isApplicable

@Suite("PluginAction.isApplicable")
struct PluginActionFilterTests {

    private func selection(
        _ text: String = "hello",
        isEditable: Bool = false,
        bundleID: String? = nil
    ) -> TextSelection {
        TextSelection(text: text, bounds: .zero, isEditable: isEditable, bundleIdentifier: bundleID)
    }

    private func action(
        minLength: Int? = nil,
        maxLength: Int? = nil,
        regex: String? = nil,
        appFilter: [String]? = nil,
        appExclude: [String]? = nil
    ) -> PluginAction {
        PluginAction(definition: PluginDefinition(
            name: "Test", icon: "star", type: .url,
            regex: regex, appFilter: appFilter, appExclude: appExclude,
            minLength: minLength, maxLength: maxLength
        ))
    }

    // MARK: - No filters

    @Test func noFiltersAlwaysApplicable() {
        #expect(action().isApplicable(for: selection("anything")))
        #expect(action().isApplicable(for: selection("", bundleID: nil)))
    }

    // MARK: - Length constraints

    @Test func minLengthExcludesShortText() {
        let a = action(minLength: 5)
        #expect(!a.isApplicable(for: selection("hi")))
        #expect(!a.isApplicable(for: selection("1234")))   // one short of minimum
        #expect(a.isApplicable(for: selection("12345")))   // exactly at minimum
        #expect(a.isApplicable(for: selection("longer text")))
    }

    @Test func maxLengthExcludesLongText() {
        let a = action(maxLength: 5)
        #expect(a.isApplicable(for: selection("hi")))
        #expect(a.isApplicable(for: selection("12345")))   // exactly at maximum
        #expect(!a.isApplicable(for: selection("123456"))) // one over maximum
    }

    @Test func lengthBoundsAreInclusive() {
        let a = action(minLength: 3, maxLength: 5)
        #expect(!a.isApplicable(for: selection("ab")))
        #expect(a.isApplicable(for: selection("abc")))
        #expect(a.isApplicable(for: selection("abcde")))
        #expect(!a.isApplicable(for: selection("abcdef")))
    }

    // MARK: - Regex filter

    @Test func regexAllowsMatchingText() {
        let a = action(regex: "^https?://")
        #expect(a.isApplicable(for: selection("https://example.com")))
        #expect(a.isApplicable(for: selection("http://foo.bar")))
        #expect(!a.isApplicable(for: selection("ftp://foo.bar")))
        #expect(!a.isApplicable(for: selection("plain text")))
    }

    @Test func regexIsCaseSensitive() {
        let a = action(regex: "^Hello")
        #expect(a.isApplicable(for: selection("Hello world")))
        #expect(!a.isApplicable(for: selection("hello world")))
    }

    @Test func regexCanMatchAnywhere() {
        let a = action(regex: "\\d+")
        #expect(a.isApplicable(for: selection("order 42")))
        #expect(!a.isApplicable(for: selection("no digits here")))
    }

    // MARK: - App filter

    @Test func appFilterAllowsListedBundleIDs() {
        let a = action(appFilter: ["com.apple.Safari", "com.google.Chrome"])
        #expect(a.isApplicable(for: selection(bundleID: "com.apple.Safari")))
        #expect(a.isApplicable(for: selection(bundleID: "com.google.Chrome")))
        #expect(!a.isApplicable(for: selection(bundleID: "com.apple.Notes")))
    }

    @Test func appFilterBlocksNilBundleID() {
        let a = action(appFilter: ["com.apple.Safari"])
        #expect(!a.isApplicable(for: selection(bundleID: nil)))
    }

    // MARK: - App exclusion

    @Test func appExcludeBlocksListedBundleID() {
        let a = action(appExclude: ["com.apple.Terminal"])
        #expect(!a.isApplicable(for: selection(bundleID: "com.apple.Terminal")))
        #expect(a.isApplicable(for: selection(bundleID: "com.apple.Safari")))
    }

    @Test func appExcludePassesNilBundleID() {
        // No bundle ID means the app can't be matched to the exclusion list
        let a = action(appExclude: ["com.apple.Terminal"])
        #expect(a.isApplicable(for: selection(bundleID: nil)))
    }

    // MARK: - Combined filters

    @Test func allFiltersMustPassTogether() {
        let a = action(minLength: 5, regex: "\\d", appFilter: ["com.apple.Safari"])
        #expect(a.isApplicable(for: selection("abc12", bundleID: "com.apple.Safari")))   // all pass
        #expect(!a.isApplicable(for: selection("123", bundleID: "com.apple.Safari")))    // too short
        #expect(!a.isApplicable(for: selection("hello", bundleID: "com.apple.Safari")))  // no digit
        #expect(!a.isApplicable(for: selection("abc12", bundleID: "com.apple.Notes")))   // wrong app
    }
}

// MARK: - copyTransform

// Serialized because tests write to NSPasteboard.general
@Suite("PluginAction copyTransform", .serialized)
struct CopyTransformTests {

    private func transformed(_ text: String, using transform: PluginDefinition.TextTransform) -> String? {
        let def = PluginDefinition(name: "T", icon: "s", type: .copyTransform, transform: transform)
        let action = PluginAction(definition: def)
        let selection = TextSelection(text: text, bounds: .zero, isEditable: false, bundleIdentifier: nil)

        let previous = NSPasteboard.general.string(forType: .string)
        defer {
            NSPasteboard.general.clearContents()
            if let previous { NSPasteboard.general.setString(previous, forType: .string) }
        }

        action.execute(with: selection)
        return NSPasteboard.general.string(forType: .string)
    }

    @Test func uppercase() { #expect(transformed("hello world", using: .uppercase) == "HELLO WORLD") }
    @Test func lowercase() { #expect(transformed("HELLO WORLD", using: .lowercase) == "hello world") }
    @Test func titlecase() { #expect(transformed("hello world", using: .titlecase) == "Hello World") }
    @Test func capitalize() { #expect(transformed("hello world", using: .capitalize) == "Hello world") }
    @Test func trimWhitespace() { #expect(transformed("  hello  ", using: .trimWhitespace) == "hello") }

    @Test func base64RoundTrip() throws {
        let encoded = try #require(transformed("SnapBar", using: .base64Encode))
        #expect(encoded == "U25hcEJhcg==")
        #expect(transformed(encoded, using: .base64Decode) == "SnapBar")
    }

    @Test func urlEncodeDecodeRoundTrip() throws {
        let encoded = try #require(transformed("hello world & more", using: .urlEncode))
        #expect(encoded.contains("%20") || encoded.contains("+"))
        #expect(transformed(encoded, using: .urlDecode) == "hello world & more")
    }

    @Test func markdownBold() { #expect(transformed("text", using: .markdownBold) == "**text**") }
    @Test func markdownItalic() { #expect(transformed("text", using: .markdownItalic) == "*text*") }

    @Test func markdownCodeInlineForSingleLine() {
        #expect(transformed("code", using: .markdownCode) == "`code`")
    }

    @Test func markdownCodeBlockForMultipleLines() {
        let result = transformed("line1\nline2", using: .markdownCode)
        #expect(result == "```\nline1\nline2\n```")
    }

    @Test func countWords() {
        #expect(transformed("one two three", using: .countWords) == "3 words")
        #expect(transformed("  spaced  out  ", using: .countWords) == "2 words")
    }

    @Test func countCharacters() {
        #expect(transformed("hello", using: .countCharacters) == "5 characters")
    }

    @Test func sortLines() {
        #expect(transformed("banana\napple\ncherry", using: .sortLines) == "apple\nbanana\ncherry")
    }

    @Test func reverseLines() {
        #expect(transformed("a\nb\nc", using: .reverseLines) == "c\nb\na")
    }

    @Test func removeBlankLines() {
        #expect(transformed("a\n\nb\n   \nc", using: .removeBlankLines) == "a\nb\nc")
    }
}

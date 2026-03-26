# SnapBar

A lightweight, native macOS text selection toolbar — like PopClip, but open source and built for macOS Tahoe.

Select any text, and SnapBar appears with quick actions: copy, search, transform, open links, and more. Extend it with simple YAML plugins.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

<p align="center">
  <img src="screenshots/demo.gif" alt="SnapBar demo" width="600">
</p>

## Features

- **Instant toolbar** — appears automatically when you select text in any app
- **Built-in actions** — Copy, Cut, Paste, Search, Open Link, Dictionary
- **13 text transforms** — uppercase, lowercase, title case, Base64, URL encode, Markdown formatting, sort lines, and more
- **Plugin system** — extend with simple YAML/JSON files, hot-reloaded
- **6 plugin types** — URL, script, key combo, Shortcuts.app, macOS Services, text transforms
- **Liquid Glass UI** — native macOS Tahoe design
- **Keyboard mode** — press `⌃⌥S` to summon the toolbar with arrow-key navigation
- **Multi-monitor support** — toolbar positions correctly on any screen
- **Tiny footprint** — ~1.5 MB, pure Swift, no dependencies
- **Launch at Login** — via SMAppService

## Installation

### Build from source

Requires Xcode 26+ and macOS 26+.

```bash
git clone https://github.com/juergen-kc/SnapBar.git
cd SnapBar
xcodebuild -project SnapBar.xcodeproj -scheme SnapBar -configuration Release build CONFIGURATION_BUILD_DIR=/Applications
open /Applications/SnapBar.app
```

### First launch

1. SnapBar will ask for **Accessibility** permission — this is required to detect text selection
2. Grant access in **System Settings → Privacy & Security → Accessibility**
3. Select any text — the toolbar appears automatically

## Usage

### Built-in Actions

| Action | Description |
|--------|-------------|
| **Copy** | Copy selected text to clipboard |
| **Cut** | Cut from editable fields |
| **Paste** | Paste clipboard content |
| **Search** | Google search the selection |
| **Open Link** | Detect and open URLs |
| **Dictionary** | Look up words in Dictionary.app |

### Starter Plugins (auto-installed)

Translate, UPPERCASE, lowercase, Title Case, Word Count, Base64 Encode/Decode, Maps, Email, Bold (Markdown)

### Keyboard Mode

Press **⌃⌥S** (Control + Option + S) to summon the toolbar at the current selection. Use arrow keys to navigate and Return to execute.

## Creating Plugins

Plugins live in `~/.snapbar/plugins/` as `.yaml` or `.json` files. Changes are hot-reloaded automatically.

### Quick start — URL plugin

```yaml
name: Stack Overflow
icon: magnifyingglass.circle
type: url
url: https://stackoverflow.com/search?q={text}
```

### Text transform plugin

```yaml
name: SHOUT
icon: megaphone.fill
type: copy_transform
transform: uppercase
```

### Script plugin

```yaml
name: Word Frequency
icon: chart.bar
type: script
script: echo "$SNAPBAR_TEXT" | tr ' ' '\n' | sort | uniq -c | sort -rn | head -10
```

### Key combo plugin

```yaml
name: Comment Line
icon: text.badge.minus
type: key_combo
key_combo: cmd+/
app_filter:
  - com.apple.dt.Xcode
```

### Shortcuts plugin

```yaml
name: Summarize
icon: text.badge.star
type: shortcut
shortcut_name: Summarize Text
```

### macOS Services plugin

```yaml
name: Add to Notes
icon: note.text
type: service
service_name: Add to Notes
```

### Plugin reference

#### Required fields

| Field | Description |
|-------|-------------|
| `name` | Display name in the toolbar |
| `icon` | SF Symbol name (e.g. `star.fill`) or emoji |
| `type` | `url` · `copy_transform` · `script` · `key_combo` · `shortcut` · `service` |

#### Type-specific fields

| Field | Used by | Description |
|-------|---------|-------------|
| `url` | `url` | URL template with `{text}` placeholder |
| `transform` | `copy_transform` | Transform name (see below) |
| `script` | `script` | Shell command to execute |
| `script_interpreter` | `script` | Interpreter path (default: `/bin/bash`) |
| `key_combo` | `key_combo` | Keystroke, e.g. `cmd+shift+k` |
| `shortcut_name` | `shortcut` | Name of macOS Shortcut |
| `service_name` | `service` | Name of macOS Service |

#### Available transforms

`uppercase` · `lowercase` · `titlecase` · `capitalize` · `trim_whitespace` · `base64_encode` · `base64_decode` · `url_encode` · `url_decode` · `markdown_bold` · `markdown_italic` · `markdown_code` · `count_words` · `count_characters` · `sort_lines` · `reverse_lines` · `remove_blank_lines`

#### Optional context filters

| Field | Description |
|-------|-------------|
| `regex` | Only show when selected text matches this pattern |
| `min_length` | Minimum text length to show this action |
| `max_length` | Maximum text length to show this action |
| `app_filter` | List of bundle IDs — only show in these apps |
| `app_exclude` | List of bundle IDs — hide in these apps |

### Install via snippet

You can also install plugins via the **Settings → Plugins → Install Snippet** panel. Paste a snippet starting with `#snapbar`:

```
#snapbar
name: DuckDuckGo
icon: bird
type: url
url: https://duckduckgo.com/?q={text}
```

## Settings

Access settings from the menu bar icon → **Settings**, or use the keyboard shortcut.

- **General** — enable/disable, toolbar position (above/below), toolbar size, excluded apps
- **Actions** — enable/disable and reorder built-in actions
- **Plugins** — view installed plugins, install snippets, open plugins folder
- **App** — version info, accessibility status, launch at login

## Architecture

```
Sources/
├── App/           # App lifecycle, state, menu bar, logging
├── Actions/       # Built-in action definitions
├── Plugins/       # Plugin loading, execution, file watching
├── Toolbar/       # Floating toolbar UI (SwiftUI + NSPanel)
├── Selection/     # Accessibility API text selection detection
└── Settings/      # Settings window UI
```

- **Pure Swift 6** with strict concurrency
- **No third-party dependencies**
- **SwiftUI** for all UI
- **Accessibility API** for text selection detection
- **NSPanel** for focus-preserving floating toolbar

## License

MIT — see [LICENSE](LICENSE)

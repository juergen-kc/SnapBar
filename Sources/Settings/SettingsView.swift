import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ActionsSettingsView()
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }

            PluginsSettingsView()
                .tabItem {
                    Label("Plugins", systemImage: "puzzlepiece.extension")
                }

            AppSettingsView()
                .tabItem {
                    Label("App", systemImage: "app.badge.checkmark")
                }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Appearance") {
                Toggle("Appear automatically on text selection", isOn: $state.appearAutomatically)

                Picker("Show toolbar", selection: $state.toolbarPosition) {
                    Text("Above selection").tag(ToolbarPosition.above)
                    Text("Below selection").tag(ToolbarPosition.below)
                }

                Picker("Size", selection: $state.toolbarSize) {
                    Text("Small").tag(ToolbarSize.small)
                    Text("Medium").tag(ToolbarSize.medium)
                    Text("Large").tag(ToolbarSize.large)
                }

                Picker("Search engine", selection: $state.searchEngine) {
                    ForEach(SearchEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
            }

            Section("Excluded Apps") {
                ExcludedAppsView()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Excluded Apps

struct ExcludedAppsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.excludedApps.isEmpty {
                Text("No excluded apps")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(Array(appState.excludedApps).sorted(), id: \.self) { bundleID in
                    HStack {
                        if let appName = appName(for: bundleID) {
                            Text(appName)
                        } else {
                            Text(bundleID)
                                .font(.caption.monospaced())
                        }
                        Spacer()
                        Button(role: .destructive) {
                            appState.excludedApps.remove(bundleID)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("Add App...") {
                addRunningApp()
            }
        }
    }

    private func addRunningApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url),
           let bundleID = bundle.bundleIdentifier {
            appState.excludedApps.insert(bundleID)
        }
    }

    private func appName(for bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { Bundle(url: $0) }?
            .infoDictionary?["CFBundleName"] as? String
    }
}

// MARK: - Actions Settings

struct ActionsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Actions") {
                Text("Drag to reorder. Uncheck to disable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List {
                    ForEach($state.enabledActions) { $config in
                        HStack {
                            Toggle(isOn: $config.isEnabled) {
                                if let action = ActionRegistry.action(for: config.id) {
                                    Label(action.title, systemImage: action.icon)
                                } else {
                                    Text(config.id)
                                }
                            }
                        }
                    }
                    .onMove { from, to in
                        appState.enabledActions.move(fromOffsets: from, toOffset: to)
                        // Update order values
                        for (index, _) in appState.enabledActions.enumerated() {
                            appState.enabledActions[index].order = index
                        }
                    }
                }
                .listStyle(.bordered)
                .frame(height: 200)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Plugins Settings

struct PluginsSettingsView: View {
    @State private var plugins: [PluginDefinition] = []
    @State private var snippetText: String = ""
    @State private var snippetError: String?
    @State private var snippetSuccess: String?

    var body: some View {
        Form {
            Section("Installed Plugins") {
                if plugins.isEmpty {
                    Text("No plugins installed")
                        .foregroundStyle(.secondary)
                } else {
                    List(plugins) { plugin in
                        HStack {
                            Image(systemName: plugin.icon)
                                .frame(width: 20)
                            VStack(alignment: .leading) {
                                Text(plugin.name)
                                    .fontWeight(.medium)
                                Text(plugin.type.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.bordered)
                    .frame(height: 150)
                }

                Button("Open Plugins Folder") {
                    NSWorkspace.shared.open(PluginLoader.pluginsDirectory)
                }

                Button("Reload Plugins") {
                    ActionRegistry.reloadPlugins()
                    plugins = PluginLoader.loadAll()
                }
            }

            Section {
                DisclosureGroup("Install Snippet") {
                    Text("Paste a snippet starting with `#snapbar` to install a custom plugin.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .topLeading) {
                        if snippetText.isEmpty {
                            Text("""
                            #snapbar
                            name: My Plugin
                            icon: star.fill
                            type: url
                            url: https://example.com/?q={text}
                            """)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                        }
                        TextEditor(text: $snippetText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                    }
                    .frame(height: 120)

                    DisclosureGroup("Snippet Format Reference") {
                        VStack(alignment: .leading, spacing: 8) {
                            Group {
                                Text("**Required fields:**")
                                Text("`name` — display name\n`icon` — SF Symbol or emoji\n`type` — plugin type (see below)")
                                    .font(.system(.caption, design: .monospaced))
                            }
                            Divider()
                            Group {
                                Text("**Plugin types:**")
                                VStack(alignment: .leading, spacing: 4) {
                                    snippetHelpRow("url", "Open a URL. Use `{text}` as placeholder.\n  `url: https://google.com/search?q={text}`")
                                    snippetHelpRow("copy_transform", "Transform text in-place.\n  `transform: uppercase` · `lowercase` · `titlecase`\n  `trim_whitespace` · `sort_lines` · `base64_encode`")
                                    snippetHelpRow("key_combo", "Simulate a keystroke.\n  `key_combo: cmd+shift+k`")
                                    snippetHelpRow("script", "Run a shell script. Text via `$SNAPBAR_TEXT`.\n  `script: echo $SNAPBAR_TEXT | tr a-z A-Z`")
                                    snippetHelpRow("shortcut", "Run a macOS Shortcut.\n  `shortcut_name: My Shortcut`")
                                    snippetHelpRow("service", "Invoke a macOS Service.\n  `service_name: Summarize`")
                                }
                                .font(.system(.caption, design: .monospaced))
                            }
                            Divider()
                            Group {
                                Text("**Optional filters:**")
                                Text("`regex` — only show when text matches\n`min_length` / `max_length` — text length bounds\n`app_filter` — only in these apps (bundle IDs)\n`app_exclude` — hide in these apps")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    }

                    HStack {
                        Button("Install Snippet") {
                            installSnippet()
                        }
                        .disabled(snippetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let error = snippetError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                        if let success = snippetSuccess {
                            Text(success)
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            plugins = PluginLoader.loadAll()
        }
    }

    private func snippetHelpRow(_ type: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("**\(type)**")
            Text(desc)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func installSnippet() {
        snippetError = nil
        snippetSuccess = nil

        guard let definition = PluginLoader.parseSnippet(snippetText) else {
            snippetError = "Invalid snippet format. Must start with #snapbar."
            return
        }

        do {
            try PluginLoader.install(definition)
            ActionRegistry.reloadPlugins()
            plugins = PluginLoader.loadAll()
            snippetSuccess = "Installed \"\(definition.name)\" successfully!"
            snippetText = ""
        } catch {
            snippetError = "Failed to save: \(error.localizedDescription)"
        }
    }
}

// MARK: - App Settings

struct AppSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            }

            Section("Keyboard Shortcut") {
                LabeledContent("Summon Toolbar", value: "⌃⌥S")
                    .font(.callout)
                Text("Press with text selected to open in keyboard mode. Use arrow keys to navigate, Return to execute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    if AccessibilityHelper.isTrusted() {
                        Label("Accessibility: Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Accessibility: Not Granted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Grant Access") {
                            AccessibilityHelper.requestAccess()
                        }
                    }
                }
            }

            Section {
                @Bindable var state = appState
                Toggle("Start at Login", isOn: $state.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

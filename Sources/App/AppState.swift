import SwiftUI
import ServiceManagement

@MainActor
@Observable
final class AppState {
    static weak var shared: AppState?

    // MARK: - General Settings
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    var appearAutomatically: Bool {
        didSet { UserDefaults.standard.set(appearAutomatically, forKey: "appearAutomatically") }
    }

    private var _isUpdatingLaunchAtLogin = false
    var launchAtLogin: Bool {
        didSet {
            guard !_isUpdatingLaunchAtLogin else { return }
            _isUpdatingLaunchAtLogin = true
            defer { _isUpdatingLaunchAtLogin = false }

            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                DebugLog.log("SMAppService error: \(error)")
                launchAtLogin = !launchAtLogin
            }
        }
    }

    var toolbarPosition: ToolbarPosition {
        didSet { UserDefaults.standard.set(toolbarPosition.rawValue, forKey: "toolbarPosition") }
    }
    var toolbarSize: ToolbarSize {
        didSet { UserDefaults.standard.set(toolbarSize.rawValue, forKey: "toolbarSize") }
    }
    var excludedApps: Set<String> {
        didSet { UserDefaults.standard.set(Array(excludedApps), forKey: "excludedApps") }
    }
    var searchEngine: SearchEngine {
        didSet { UserDefaults.standard.set(searchEngine.rawValue, forKey: "searchEngine") }
    }

    // MARK: - Actions
    var enabledActions: [ActionConfig] {
        didSet { saveActions() }
    }

    init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.object(forKey: "isEnabled") as? Bool ?? true
        self.appearAutomatically = defaults.object(forKey: "appearAutomatically") as? Bool ?? true
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.toolbarPosition = defaults.string(forKey: "toolbarPosition").flatMap(ToolbarPosition.init) ?? .above
        self.toolbarSize = defaults.string(forKey: "toolbarSize").flatMap(ToolbarSize.init) ?? .medium
        self.excludedApps = Set(defaults.stringArray(forKey: "excludedApps") ?? [])
        self.searchEngine = defaults.string(forKey: "searchEngine").flatMap(SearchEngine.init) ?? .google
        self.enabledActions = Self.loadActions()
    }

    private func saveActions() {
        if let data = try? JSONEncoder().encode(enabledActions) {
            UserDefaults.standard.set(data, forKey: "enabledActions")
        }
    }

    private static func loadActions() -> [ActionConfig] {
        guard let data = UserDefaults.standard.data(forKey: "enabledActions"),
              let actions = try? JSONDecoder().decode([ActionConfig].self, from: data) else {
            return ActionConfig.defaults
        }
        // Merge in any new built-in actions that were added in updates
        let existingIDs = Set(actions.map(\.id))
        return actions + ActionConfig.defaults
            .filter { !existingIDs.contains($0.id) }
            .enumerated().map { ActionConfig(id: $1.id, isEnabled: true, order: actions.count + $0) }
    }
}

// MARK: - Supporting Types

enum ToolbarPosition: String, CaseIterable {
    case above
    case below
}

enum ToolbarSize: String, CaseIterable {
    case small
    case medium
    case large

    var iconSize: CGFloat {
        switch self {
        case .small: 13
        case .medium: 16
        case .large: 20
        }
    }

    var buttonSize: CGFloat {
        switch self {
        case .small: 28
        case .medium: 36
        case .large: 44
        }
    }
}

enum SearchEngine: String, CaseIterable {
    case google
    case duckduckgo
    case bing
    case ecosia
    case brave
    case startpage

    var displayName: String {
        switch self {
        case .google: "Google"
        case .duckduckgo: "DuckDuckGo"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        case .brave: "Brave"
        case .startpage: "Startpage"
        }
    }

    private var searchBaseURL: String {
        switch self {
        case .google: "https://www.google.com/search?q="
        case .duckduckgo: "https://duckduckgo.com/?q="
        case .bing: "https://www.bing.com/search?q="
        case .ecosia: "https://www.ecosia.org/search?q="
        case .brave: "https://search.brave.com/search?q="
        case .startpage: "https://www.startpage.com/do/search?q="
        }
    }

    func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: searchBaseURL + encoded)
    }
}

struct ActionConfig: Identifiable, Codable, Equatable {
    let id: String
    var isEnabled: Bool
    var order: Int

    static let defaults: [ActionConfig] = [
        "copy", "cut", "paste", "pastePlainText", "search",
        "openLink", "dictionary", "spelling", "revealInFinder",
    ].enumerated().map { ActionConfig(id: $1, isEnabled: true, order: $0) }
}

struct TextSelection: Equatable {
    let text: String
    let bounds: CGRect  // Screen coordinates of the selection
    let isEditable: Bool
    let bundleIdentifier: String?

    /// Create a selection, defaulting bundleIdentifier to the frontmost app.
    init(text: String, bounds: CGRect, isEditable: Bool, bundleIdentifier: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
        self.text = text
        self.bounds = bounds
        self.isEditable = isEditable
        self.bundleIdentifier = bundleIdentifier
    }

    /// Whether the selection contains meaningful (non-whitespace) content
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

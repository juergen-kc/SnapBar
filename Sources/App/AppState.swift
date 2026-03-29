import SwiftUI
import Observation
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

    // MARK: - Runtime State (not persisted)
    var currentSelection: TextSelection?
    var isToolbarVisible = false

    init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.object(forKey: "isEnabled") as? Bool ?? true
        self.appearAutomatically = defaults.object(forKey: "appearAutomatically") as? Bool ?? true
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.toolbarPosition = ToolbarPosition(rawValue: defaults.string(forKey: "toolbarPosition") ?? "") ?? .above
        self.toolbarSize = ToolbarSize(rawValue: defaults.string(forKey: "toolbarSize") ?? "") ?? .medium
        self.excludedApps = Set(defaults.stringArray(forKey: "excludedApps") ?? [])
        self.searchEngine = SearchEngine(rawValue: defaults.string(forKey: "searchEngine") ?? "") ?? .google
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
        var merged = actions
        for defaultAction in ActionConfig.defaults where !actions.contains(where: { $0.id == defaultAction.id }) {
            merged.append(ActionConfig(id: defaultAction.id, isEnabled: true, order: merged.count))
        }
        return merged
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

    func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let template: String
        switch self {
        case .google: template = "https://www.google.com/search?q=\(encoded)"
        case .duckduckgo: template = "https://duckduckgo.com/?q=\(encoded)"
        case .bing: template = "https://www.bing.com/search?q=\(encoded)"
        case .ecosia: template = "https://www.ecosia.org/search?q=\(encoded)"
        case .brave: template = "https://search.brave.com/search?q=\(encoded)"
        case .startpage: template = "https://www.startpage.com/do/search?q=\(encoded)"
        }
        return URL(string: template)
    }
}

struct ActionConfig: Identifiable, Codable, Equatable {
    let id: String
    var isEnabled: Bool
    var order: Int

    static let defaults: [ActionConfig] = [
        ActionConfig(id: "copy", isEnabled: true, order: 0),
        ActionConfig(id: "cut", isEnabled: true, order: 1),
        ActionConfig(id: "paste", isEnabled: true, order: 2),
        ActionConfig(id: "pastePlainText", isEnabled: true, order: 3),
        ActionConfig(id: "search", isEnabled: true, order: 4),
        ActionConfig(id: "openLink", isEnabled: true, order: 5),
        ActionConfig(id: "dictionary", isEnabled: true, order: 6),
        ActionConfig(id: "spelling", isEnabled: true, order: 7),
        ActionConfig(id: "revealInFinder", isEnabled: true, order: 8),
    ]
}

struct TextSelection: Equatable {
    let text: String
    let bounds: CGRect  // Screen coordinates of the selection
    let isEditable: Bool
    let bundleIdentifier: String?

    /// Whether the selection contains meaningful (non-whitespace) content
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

import AppKit

/// Protocol for toolbar actions
protocol Action: Identifiable, Sendable {
    var id: String { get }
    var title: String { get }
    var icon: String { get }  // SF Symbol name
    /// Whether this action should be visible for the given selection
    func isApplicable(for selection: TextSelection) -> Bool
    /// Execute the action
    func execute(with selection: TextSelection)
}

/// Registry of all available actions (built-in + plugins)
@MainActor
enum ActionRegistry {
    private(set) static var builtInActions: [any Action] = [
        CopyAction(),
        CutAction(),
        PasteAction(),
        SearchAction(),
        OpenLinkAction(),
        DictionaryAction(),
    ]

    private(set) static var pluginActions: [PluginAction] = []

    static var allActions: [any Action] {
        builtInActions + pluginActions
    }

    static func reloadPlugins() {
        let definitions = PluginLoader.loadAll()
        pluginActions = definitions.map { PluginAction(definition: $0) }
    }

    static func action(for id: String) -> (any Action)? {
        allActions.first { $0.id == id }
    }

    static func applicableActions(for selection: TextSelection, config: [ActionConfig]) -> [any Action] {
        // Built-in actions filtered by config
        let builtIn = config
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }
            .compactMap { cfg in builtInActions.first { $0.id == cfg.id } }
            .filter { $0.isApplicable(for: selection) }

        // Plugin actions (always appended after built-ins, filtered by their own context rules)
        let plugins = pluginActions.filter { $0.isApplicable(for: selection) }

        return builtIn + plugins
    }
}

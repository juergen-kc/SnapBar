import SwiftUI

/// Represents either a single action or a group of actions in the toolbar.
enum ToolbarItem: Identifiable {
    case single(any Action)
    case group(name: String, icon: String, actions: [any Action])

    var id: String {
        switch self {
        case .single(let action): action.id
        case .group(let name, _, _): "group.\(name)"
        }
    }

    /// Build toolbar items from a flat list of actions, grouping plugins that share a `group` field.
    static func build(from actions: [any Action]) -> [ToolbarItem] {
        var items: [ToolbarItem] = []
        var groups: [String: (icon: String, actions: [any Action])] = [:]
        var groupOrder: [String] = []

        for action in actions {
            if let plugin = action as? PluginAction, let groupName = plugin.definition.group {
                if groups[groupName] == nil { groupOrder.append(groupName) }
                groups[groupName, default: (icon: plugin.icon, actions: [])].actions.append(action)
            } else {
                items.append(.single(action))
            }
        }

        // Append groups in order they first appeared
        for name in groupOrder {
            guard let group = groups[name] else { continue }
            if group.actions.count == 1 {
                items.append(.single(group.actions[0]))
            } else {
                items.append(.group(name: name, icon: group.icon, actions: group.actions))
            }
        }

        return items
    }
}

/// The floating toolbar view using Liquid Glass design.
struct ToolbarView: View {
    let actions: [any Action]
    let selection: TextSelection
    let onDismiss: () -> Void
    let keyboardMode: Bool

    @Namespace private var toolbarNamespace
    @Environment(AppState.self) private var appState
    @State private var focusedIndex: Int = 0
    @State private var expandedGroup: String?

    private var toolbarItems: [ToolbarItem] {
        ToolbarItem.build(from: actions)
    }

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(toolbarItems.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case .single(let action):
                        actionButton(for: action, index: index)
                            .glassEffectID(action.id, in: toolbarNamespace)
                    case .group(let name, let icon, let groupActions):
                        groupButton(name: name, icon: icon, actions: groupActions, index: index)
                            .glassEffectID("group.\(name)", in: toolbarNamespace)
                    }
                }
            }
            .padding(5)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .fixedSize()
        .onKeyPress(.leftArrow) {
            guard keyboardMode else { return .ignored }
            focusedIndex = max(0, focusedIndex - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard keyboardMode else { return .ignored }
            focusedIndex = min(toolbarItems.count - 1, focusedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard keyboardMode, toolbarItems.indices.contains(focusedIndex) else { return .ignored }
            switch toolbarItems[focusedIndex] {
            case .single(let action):
                action.execute(with: selection)
                onDismiss()
            case .group(let name, _, _):
                expandedGroup = expandedGroup == name ? nil : name
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if expandedGroup != nil {
                expandedGroup = nil
                return .handled
            }
            onDismiss()
            return .handled
        }
        .onKeyPress(keys: []) { _ in
            if !keyboardMode {
                onDismiss()
                return .handled
            }
            return .ignored
        }
    }

    private func isFocused(_ index: Int) -> Bool {
        keyboardMode && index == focusedIndex
    }

    /// Apply focus highlight styling (foreground color + background tint) used by both action and group buttons.
    private func focusHighlight<Content: View>(_ isFocused: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(isFocused ? .white : .primary)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.tint)
                }
            }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func actionButton(for action: any Action, index: Int) -> some View {
        Button {
            action.execute(with: selection)
            onDismiss()
        } label: {
            focusHighlight(isFocused(index)) {
                Image(systemName: action.icon)
                    .font(.system(size: appState.toolbarSize.iconSize, weight: .medium))
                    .frame(
                        width: appState.toolbarSize.buttonSize,
                        height: appState.toolbarSize.buttonSize
                    )
            }
        }
        .buttonStyle(.plain)
        .help(action.title)
    }

    @ViewBuilder
    private func groupButton(name: String, icon: String, actions: [any Action], index: Int) -> some View {
        let isExpanded = expandedGroup == name

        Button {
            withAnimation(.snappy(duration: 0.2)) {
                expandedGroup = isExpanded ? nil : name
            }
        } label: {
            focusHighlight(isFocused(index)) {
                HStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: appState.toolbarSize.iconSize, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: appState.toolbarSize.iconSize * 0.55, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(height: appState.toolbarSize.buttonSize)
                .padding(.horizontal, 6)
            }
        }
        .buttonStyle(.plain)
        .help(name)
        .popover(isPresented: Binding(
            get: { isExpanded },
            set: { if !$0 { expandedGroup = nil } }
        ), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(actions, id: \.id) { action in
                    Button {
                        action.execute(with: selection)
                        expandedGroup = nil
                        onDismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.icon)
                                .frame(width: 20)
                            Text(action.title)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
    }
}

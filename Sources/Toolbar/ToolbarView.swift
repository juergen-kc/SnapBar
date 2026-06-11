import SwiftUI

struct ToolbarSurfaceStyle: Equatable {
    let fallbackFillOpacity: Double
    let strokeOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    static let floatingToolbar = ToolbarSurfaceStyle(
        fallbackFillOpacity: 0.72,
        strokeOpacity: 0.16,
        shadowOpacity: 0.24,
        shadowRadius: 16,
        shadowYOffset: 8
    )

    var hasVisibleFallback: Bool {
        fallbackFillOpacity > 0
            && strokeOpacity > 0
            && shadowOpacity > 0
            && shadowRadius > 0
    }
}

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
        items += groupOrder.map { name in
            let group = groups[name]!
            return group.actions.count == 1
                ? .single(group.actions[0])
                : .group(name: name, icon: group.icon, actions: group.actions)
        }

        return items
    }
}

/// The floating toolbar view using Liquid Glass design.
struct ToolbarView: View {
    private let toolbarItems: [ToolbarItem]
    let selection: TextSelection
    let onDismiss: () -> Void
    let keyboardMode: Bool

    @Namespace private var toolbarNamespace
    @Environment(AppState.self) private var appState
    @State private var focusedIndex = 0
    @State private var expandedGroup: String?

    private static let surfaceStyle = ToolbarSurfaceStyle.floatingToolbar

    init(actions: [any Action], selection: TextSelection, onDismiss: @escaping () -> Void, keyboardMode: Bool) {
        self.toolbarItems = ToolbarItem.build(from: actions)
        self.selection = selection
        self.onDismiss = onDismiss
        self.keyboardMode = keyboardMode
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
            .background {
                Capsule()
                    .fill(.regularMaterial)
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(Self.surfaceStyle.fallbackFillOpacity))
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(Self.surfaceStyle.strokeOpacity), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(Self.surfaceStyle.shadowOpacity),
                radius: Self.surfaceStyle.shadowRadius,
                y: Self.surfaceStyle.shadowYOffset
            )
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .fixedSize()
        .padding(.bottom, 30) // Reserve space below for tooltip overlays
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
            if expandedGroup != nil { expandedGroup = nil } else { onDismiss() }
            return .handled
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
        .glassTooltip(action.title)
    }

    private func groupButton(name: String, icon: String, actions: [any Action], index: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                expandedGroup = expandedGroup == name ? nil : name
            }
        } label: {
            focusHighlight(isFocused(index)) {
                HStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: appState.toolbarSize.iconSize, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: appState.toolbarSize.iconSize * 0.55, weight: .semibold))
                        .rotationEffect(.degrees(expandedGroup == name ? 180 : 0))
                }
                .frame(height: appState.toolbarSize.buttonSize)
                .padding(.horizontal, 6)
            }
        }
        .buttonStyle(.plain)
        .glassTooltip(name)
        .popover(isPresented: Binding(
            get: { expandedGroup == name },
            set: { expandedGroup = $0 ? name : nil }
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

// MARK: - Liquid Glass tooltip

/// Tracks mouse hover via NSTrackingArea (.activeAlways) so it works on non-activating panels.
private struct HoverTracker: NSViewRepresentable {
    @Binding var isHovered: Bool

    func makeNSView(context: Context) -> HoverNSView {
        let view = HoverNSView()
        view.onHover = { isHovered in
            Task { @MainActor in self.isHovered = isHovered }
        }
        return view
    }

    func updateNSView(_ nsView: HoverNSView, context: Context) {}

    final class HoverNSView: NSView {
        var onHover: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
    }
}

private struct GlassTooltip: ViewModifier {
    let text: String
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background { HoverTracker(isHovered: $isHovered) }
            .overlay(alignment: .bottom) {
                if isHovered {
                    Text(text)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                        .fixedSize()
                        .offset(y: 30)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

extension View {
    func glassTooltip(_ text: String) -> some View {
        modifier(GlassTooltip(text: text))
    }
}

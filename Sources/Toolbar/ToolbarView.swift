import SwiftUI

/// The floating toolbar view using Liquid Glass design.
struct ToolbarView: View {
    let actions: [any Action]
    let selection: TextSelection
    let onDismiss: () -> Void
    let keyboardMode: Bool

    @Namespace private var toolbarNamespace
    @Environment(AppState.self) private var appState
    @State private var focusedIndex: Int = 0

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    actionButton(for: action, index: index)
                        .glassEffectID(action.id, in: toolbarNamespace)
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
            focusedIndex = min(actions.count - 1, focusedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard keyboardMode, actions.indices.contains(focusedIndex) else { return .ignored }
            actions[focusedIndex].execute(with: selection)
            onDismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(keys: []) { _ in
            // Dismiss on any other keypress (non-keyboard-mode)
            if !keyboardMode {
                onDismiss()
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private func actionButton(for action: any Action, index: Int) -> some View {
        let isFocused = keyboardMode && index == focusedIndex

        Button {
            action.execute(with: selection)
            onDismiss()
        } label: {
            Image(systemName: action.icon)
                .font(.system(size: appState.toolbarSize.iconSize, weight: .medium))
                .foregroundStyle(isFocused ? .white : .primary)
                .frame(
                    width: appState.toolbarSize.buttonSize,
                    height: appState.toolbarSize.buttonSize
                )
                .background {
                    if isFocused {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.tint)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(action.title)
    }
}

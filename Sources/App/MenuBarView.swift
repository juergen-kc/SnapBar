import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var state = appState

        Toggle("Enabled", isOn: $state.isEnabled)

        Divider()

        Button("Settings...") {
            // LSUIElement apps need to temporarily become regular apps to show windows
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openSettings()

            // Go back to accessory (no Dock icon) once the settings window closes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if NSApp.windows.filter({ $0.isVisible && !($0 is ToolbarPanel) }).isEmpty {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit SnapBar") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

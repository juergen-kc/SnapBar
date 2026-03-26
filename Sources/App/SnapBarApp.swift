import SwiftUI

@main
struct SnapBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.appState)
        } label: {
            Image(systemName: "text.cursor")
        }

        Settings {
            SettingsView()
                .environment(appDelegate.appState)
        }
    }
}

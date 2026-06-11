import Foundation

/// Tracks which plugin actions are currently executing (script, shortcut).
/// Observed by ToolbarView to show in-progress indicators on buttons.
@MainActor
@Observable
final class RunningState {
    static let shared = RunningState()

    private(set) var activeActionIDs: Set<String> = []

    func begin(_ id: String) { activeActionIDs.insert(id) }
    func end(_ id: String) { activeActionIDs.remove(id) }
    func contains(_ id: String) -> Bool { activeActionIDs.contains(id) }
}

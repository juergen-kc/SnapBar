import Foundation

/// Watches ~/.snapbar/plugins/ for file changes and triggers a reload.
@MainActor
final class PluginDirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let onChange: @MainActor () -> Void

    init(onChange: @MainActor @escaping () -> Void) {
        self.onChange = onChange
        startWatching()
    }

    deinit {
        source?.cancel()
    }

    private func startWatching() {
        let path = PluginLoader.pluginsDirectory.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            // Debounce: wait a moment for file writes to complete
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self?.onChange()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.source = source
    }
}

import os
import Foundation

let logger = Logger(subsystem: "com.snapbar.app", category: "SnapBar")

/// Debug logger that writes to both os_log and ~/.snapbar/debug.log
enum DebugLog {
    private nonisolated(unsafe) static let formatter = ISO8601DateFormatter()

    static let fileURL: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".snapbar/debug.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }()

    private static let maxLogSize: UInt64 = 2 * 1024 * 1024  // 2 MB

    static func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        logger.notice("\(message)")
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { handle.closeFile() }
            let size = handle.seekToEndOfFile()
            if size > maxLogSize {
                rotateLog()
            } else {
                handle.write(data)
                return
            }
        }
        try? data.write(to: fileURL)
    }

    private static func rotateLog() {
        let oldURL = fileURL.deletingLastPathComponent().appendingPathComponent("debug.old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: fileURL, to: oldURL)
    }
}
